pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// A singleton prevents duplicate schedules on multi-monitor configurations.
// All mutations go through the locked `hyprshell wallpaper` pipeline.
Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.local/state/quickshell/auto-wallpaper.json"
    readonly property var intervalSteps: [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 1440]

    property bool loaded: false
    property bool enabled: true
    property int intervalMinutes: 30
    property string mode: "sequential"
    property double lastChangeEpoch: 0
    // shuffle bookkeeping: the order to walk and how far along it we are
    property var cycle: []
    property int cycleIndex: 0
    property string cycleTheme: ""
    readonly property bool shuffle: root.mode === "shuffle"

    property string themeName: ""
    // set once the theme has actually been read; a first sighting is startup,
    // not a theme change, and must not reset the schedule on every bar reload
    property bool themeKnown: false
    property var entries: []
    readonly property var paths: root.entries.map(entry => entry.path)
    property string current: ""
    property double nowEpoch: Date.now()
    property bool busy: false
    property string pending: ""
    property var pendingNext: null
    property string lastError: ""
    property string lastAction: ""

    function wallpaperName(path) {
        const base = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
        if (!base) return "Unknown"
        return base.replace(/[-_.]+/g, " ").replace(/\b[a-z]/g, letter => letter.toUpperCase()).replace(/\s+/g, " ").trim()
    }
    function modeLabel(value) { return value === "shuffle" ? "Shuffle" : "Sequential" }
    function intervalLabel(minutes) {
        if (minutes < 60) return "Every " + minutes + " min"
        if (minutes % 60 !== 0) return "Every " + minutes + " min"
        const hours = minutes / 60
        return "Every " + hours + (hours === 1 ? " hour" : " hours")
    }
    function statusText() {
        const count = root.entries.length
        return count + " wallpaper" + (count === 1 ? "" : "s") + " · " + root.modeLabel(root.mode)
    }
    function nextText() {
        if (!root.enabled) return "Automatic switching is off"
        const target = root.pickNext().path
        if (!target) return "No other wallpaper to show"
        const minutes = root.minutesUntil()
        return "Next in " + (minutes > 0 ? minutes + " min" : "now") + " · " + root.wallpaperName(target)
    }
    // thumbnails are PNGs stored without a .png suffix, and a wallpaper path can
    // hold spaces because the theme name does ("Catppuccin Mocha")
    function fileUrl(path) { return "file://" + String(path).split("/").map(encodeURIComponent).join("/") }

    function normalize(raw) {
        const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
        const minutes = Math.floor(Number(source.intervalMinutes))
        const epoch = Math.floor(Number(source.lastChangeEpoch))
        const index = Math.floor(Number(source.cycleIndex))
        return {
            enabled: typeof source.enabled === "boolean" ? source.enabled : true,
            intervalMinutes: isFinite(minutes) && minutes >= 1 && minutes <= 1440 ? minutes : 30,
            mode: source.mode === "shuffle" ? "shuffle" : "sequential",
            lastChangeEpoch: isFinite(epoch) ? epoch : 0,
            cycle: Array.isArray(source.cycle) ? source.cycle.slice() : [],
            cycleIndex: isFinite(index) ? index : 0,
            cycleTheme: typeof source.cycleTheme === "string" ? source.cycleTheme : ""
        }
    }
    function snapshot() {
        return {enabled: root.enabled, intervalMinutes: root.intervalMinutes, mode: root.mode,
            lastChangeEpoch: root.lastChangeEpoch, cycle: root.cycle, cycleIndex: root.cycleIndex,
            cycleTheme: root.cycleTheme}
    }
    function applyConfig(raw) {
        let parsed = {}
        try { parsed = raw && String(raw).trim() ? JSON.parse(raw) : {} }
        catch (error) { root.lastError = "Invalid auto-wallpaper.json: " + error }
        const config = root.normalize(parsed)
        // a config with no epoch reads as overdue the moment the bar starts, and
        // would switch the wallpaper on first run; start the clock now so the
        // first change waits a whole interval
        if (config.enabled && config.lastChangeEpoch <= 0) config.lastChangeEpoch = Date.now()
        root.enabled = config.enabled
        root.intervalMinutes = config.intervalMinutes
        root.mode = config.mode
        root.lastChangeEpoch = config.lastChangeEpoch
        root.cycle = config.cycle
        root.cycleIndex = config.cycleIndex
        root.cycleTheme = config.cycleTheme
        root.loaded = true
        root.nowEpoch = Date.now()
        Qt.callLater(root.reconcile)
    }
    function save(patch) {
        const text = JSON.stringify(root.normalize(Object.assign(root.snapshot(), patch)), null, 2) + "\n"
        configFile.setText(text)
        root.applyConfig(text)
    }

    function shuffled(values) {
        const list = values.slice()
        for (let i = list.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const swap = list[i]; list[i] = list[j]; list[j] = swap
        }
        return list
    }
    function sameSet(left, right) {
        if (left.length !== right.length) return false
        const a = left.slice().sort(), b = right.slice().sort()
        return a.every((value, index) => value === b[index])
    }
    // a persisted shuffle order survives only while the theme is unchanged and
    // the catalog still holds exactly the same paths
    function cycleValid(list) {
        return root.cycleTheme === root.themeName && Array.isArray(root.cycle) && root.sameSet(root.cycle, list)
    }
    // Sequential advances one slot past the current wallpaper, wrapping around.
    // Shuffle steps a persisted, never-repeating order, resuming from wherever
    // the current wallpaper sits so a manual pick stays part of the rotation.
    // Pure: returns the target plus the bookkeeping the caller must persist.
    function pickNext() {
        const list = root.paths.slice()
        if (list.length <= 1) return {path: "", cycle: [], cycleIndex: 0, changed: false}
        if (!root.shuffle) {
            const at = root.current ? list.indexOf(root.current) : -1
            const step = at >= 0 ? (at + 1) % list.length : 0
            return {path: list[step], cycle: [], cycleIndex: 0, changed: list[step] !== root.current}
        }
        const valid = root.cycleValid(list)
        const order = valid ? root.cycle.slice() : root.shuffled(list)
        const at = valid ? (root.cycleIndex || 0) : (root.current ? order.indexOf(root.current) : -1)
        const step = (at + 1) % order.length
        return {path: order[step], cycle: order, cycleIndex: step, changed: order[step] !== root.current}
    }
    function elapsed() { return root.nowEpoch - Math.max(0, root.lastChangeEpoch) }
    function isDue() { return root.enabled && Math.max(0, root.elapsed()) >= root.intervalMinutes * 60000 }
    // whole minutes until the next scheduled change; -1 while automation is off
    function minutesUntil() {
        if (!root.enabled) return -1
        return Math.ceil(Math.max(1, root.intervalMinutes * 60000 - root.elapsed()) / 60000)
    }

    function setEnabled(value) {
        root.save({enabled: value === true})
        if (value === true) Qt.callLater(root.applyNext)
        else root.lastAction = "Automatic switching disabled"
    }
    function updateSchedule(patch) { root.save(patch); root.lastAction = "Schedule saved" }
    function applyNext() {
        if (root.busy) return
        const next = root.pickNext()
        if (next.changed && next.path) { root.switchTo(next.path, next); return }
        // an empty catalog is a failed listing, not a satisfied schedule: leave the
        // clock alone and relist so the next tick retries a minute later
        if (root.entries.length === 0) { root.lastAction = "No wallpapers for this theme"; root.refresh(); return }
        root.lastAction = "Already showing the only wallpaper"
        root.save({lastChangeEpoch: Date.now()})
    }
    function setWallpaper(path) { if (!root.busy && path) root.switchTo(path, null) }
    function switchTo(path, next) {
        const target = String(path || "").trim()
        if (!target) { root.lastError = "No wallpaper selected."; return }
        root.pending = target
        root.pendingNext = next
        root.lastError = ""
        // --global is what the rest of this config uses to advance a wallpaper:
        // it updates the theme links, the thumbnail cache and, in pywal mode,
        // the palette
        setProc.command = ["hyprshell", "wallpaper", "set", target, "--global"]
        root.busy = true
        setProc.running = true
    }
    function finishSwitch(code, error) {
        root.busy = false
        const applied = root.pending
        if (code === 0) {
            root.current = applied
            // start the next interval and keep the shuffle order aligned with
            // whichever wallpaper actually landed
            const patch = {lastChangeEpoch: Date.now(), cycleTheme: root.themeName}
            if (root.pendingNext) { patch.cycle = root.pendingNext.cycle; patch.cycleIndex = root.pendingNext.cycleIndex }
            root.save(patch)
            root.updateCurrent()
            root.lastAction = "Wallpaper set to " + root.wallpaperName(applied)
            root.lastError = ""
        } else {
            root.lastError = String(error || "Wallpaper change failed").trim()
        }
        root.pending = ""
        root.pendingNext = null
    }
    function reconcile() {
        if (!root.loaded || root.busy) return
        root.nowEpoch = Date.now()
        if (!root.enabled) return
        // the wallpaper also moves from keybinds and theme switches; re-anchor
        // on the tick before a scheduled pick so the rotation advances from
        // what is actually on screen rather than from a stale index
        if (root.minutesUntil() <= 1) root.updateCurrent()
        if (root.isDue()) root.applyNext()
    }
    function applyTheme(name) {
        // an unreadable staterc parses to "": no information, not a theme change
        if (!name || name === root.themeName) return
        const known = root.themeKnown
        root.themeName = name
        root.themeKnown = true
        if (!known || !root.loaded) return
        // a new theme is a new wallpaper set: let it be seen before any
        // scheduled change, and let pickNext rebuild the shuffle order
        root.save({lastChangeEpoch: Date.now(), cycle: [], cycleTheme: ""})
        root.lastAction = "Theme changed to " + name
        root.refresh(true)
    }

    // `wallpaper json` only reads the catalog and takes no
    // wallpaper lock. Thumbnail generation is deferred to a panel open, so a
    // module sitting closed in the bar costs nothing.
    function refresh(ensureThumbs) {
        if (ensureThumbs === true) { if (!cacheProc.running) cacheProc.running = true; return }
        if (!catalogProc.running) catalogProc.running = true
    }
    function updateCurrent() { if (!currentProc.running) currentProc.running = true }
    function loadCatalog(code, out, error) {
        if (code !== 0) { root.lastError = String(error || "Could not list wallpapers").trim(); catalogRetry.restart(); return }
        let list = []
        try { list = JSON.parse(out) || [] }
        catch (parseError) { root.lastError = "Could not read the wallpaper catalog: " + parseError; catalogRetry.restart(); return }
        const seen = {}, next = []
        for (const item of list) {
            const path = String(item.path || "").trim()
            if (!path || seen[path]) continue
            seen[path] = true
            // sqre is the 500x500 square crop the wallpaper cache already keeps
            next.push({path: path, thumb: String(item.sqre || "") || path, name: root.wallpaperName(path)})
        }
        root.entries = next
        root.lastError = ""
        Qt.callLater(root.reconcile)
    }

    property FileView configFile: FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onLoaded: root.applyConfig(text())
        onLoadFailed: root.applyConfig("")
        onFileChanged: reload()
    }
    // staterc changes for far more than the theme, so applyTheme filters on the
    // value rather than on the file event
    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/hypr/staterc"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const match = String(text()).match(/(?:^|\n)HYPR_THEME=["']?([^"'\n]+)/)
            root.applyTheme(match ? match[1].trim() : "")
        }
    }
    property Process catalogProc: Process {
        command: ["hyprshell", "wallpaper", "json"]
        stdout: StdioCollector { id: catalogOut; waitForEnd: true }
        stderr: StdioCollector { id: catalogErr; waitForEnd: true }
        onExited: code => root.loadCatalog(code, catalogOut.text, catalogErr.text)
    }
    property Process currentProc: Process {
        // --global reads wall.set, the link `wallpaper set --global` writes; a
        // bare `get` resolves the per-backend link instead, which stays stale
        command: ["hyprshell", "wallpaper", "get", "--global"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.current = String(text).trim().split("\n").pop() }
    }
    // fills any gap in the thumbnail cache for the active theme, then relists
    property Process cacheProc: Process {
        command: ["hyprshell", "wallpaper/wallpaper.cache"]
        onExited: root.refresh()
    }
    property Process setProc: Process {
        stderr: StdioCollector { id: setErr; waitForEnd: true }
        onExited: code => root.finishSwitch(code, setErr.text)
    }
    // a failed listing leaves entries stale, and nothing else would ever relist
    property Timer catalogRetry: Timer { interval: 30000; onTriggered: root.refresh() }
    // in-memory check; reconcile spawns a process only when a change is really
    // due, so an idle schedule costs a comparison a minute
    property Timer scheduleTimer: Timer {
        interval: 60000
        running: root.loaded
        repeat: true
        onTriggered: root.reconcile()
    }
    property IpcHandler ipc: IpcHandler {
        target: "wallpaper"
        function next(): void { root.applyNext() }
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        function toggle(): void { root.setEnabled(!root.enabled) }
        function status(): string {
            return "enabled=" + root.enabled + " mode=" + root.mode + " interval=" + root.intervalMinutes
                + " theme=\"" + root.themeName + "\" count=" + root.entries.length
                + " current=\"" + root.wallpaperName(root.current) + "\" next=\"" + root.nextText() + "\""
                + (root.lastError ? " error=\"" + root.lastError + "\"" : "")
        }
    }

    Component.onCompleted: {
        root.nowEpoch = Date.now()
        root.updateCurrent()
        root.refresh()
    }
}

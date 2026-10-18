pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.local/state/quickshell/auto-wallpaper.json"
    readonly property var intervalSteps: [5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 1440]

    readonly property string libraryPath: Quickshell.env("HOME") + "/.local/lib/hypr"

    property bool loaded: false
    property bool enabled: true
    property int intervalMinutes: 30
    property string mode: "sequential"
    property string scope: "global"
    property string workspaceTheme: ""
    property var workspaceWallpapers: ({})
    readonly property bool perWorkspace: root.scope === "workspace"
    readonly property bool rotationEnabled: root.enabled && !root.perWorkspace
    readonly property int workspaceId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? 0
    readonly property string workspaceName: Hyprland.focusedMonitor?.activeWorkspace?.name ?? ""
    readonly property string selectedWallpaper: root.perWorkspace ? root.workspaceWallpaper(root.workspaceId) : root.current
    readonly property var workspaceTargets: root.perWorkspace ? Hyprland.monitors.values
        .filter(monitor => monitor.activeWorkspace && monitor.activeWorkspace.id > 0)
        .map(monitor => ({output: monitor.name, path: root.workspaceWallpaper(monitor.activeWorkspace.id)})) : []
    property var appliedWallpapers: ({})
    property var failedWallpapers: ({})
    onWorkspaceTargetsChanged: {
        root.failedWallpapers = ({})
        const applied = {}
        for (const target of root.workspaceTargets)
            if (root.appliedWallpapers[target.output]) applied[target.output] = root.appliedWallpapers[target.output]
        root.appliedWallpapers = applied
        Qt.callLater(root.reconcile)
    }
    property double lastChangeEpoch: 0
    property var cycle: []
    property int cycleIndex: 0
    property string cycleTheme: ""
    readonly property bool shuffle: root.mode === "shuffle"

    property string themeName: ""
    property bool themeKnown: false
    property var entries: []
    readonly property var paths: root.entries.map(entry => entry.path)
    property string current: ""
    property double nowEpoch: Date.now()
    readonly property bool busy: setProcess.running
    property string pending: ""
    property string pendingOutput: ""
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
    function workspaceWallpaper(id) {
        if (id <= 0 || root.paths.length === 0) return root.current
        const chosen = root.workspaceTheme === root.themeName ? root.workspaceWallpapers[String(id)] : ""
        return chosen && root.paths.includes(chosen) ? chosen : root.paths[(id - 1) % root.paths.length]
    }
    function setScope(value) {
        if (root.busy || value === root.scope || !["global", "workspace"].includes(value)) return
        root.lastError = ""
        root.appliedWallpapers = ({})
        root.failedWallpapers = ({})
        root.save({scope: value, lastChangeEpoch: Date.now()})
        if (value === "global" && root.current) root.switchTo(root.current, null, "")
        root.lastAction = value === "workspace" ? "Per workspace wallpapers enabled" : "Global wallpaper enabled"
    }
    function nextText() {
        if (root.perWorkspace) return "Workspace " + root.workspaceName + " · " + root.wallpaperName(root.selectedWallpaper)
        if (!root.enabled) return "Automatic switching is off"
        const target = root.pickNext().path
        if (!target) return "No other wallpaper to show"
        const minutes = root.minutesUntil()
        return "Next in " + (minutes > 0 ? minutes + " min" : "now") + " · " + root.wallpaperName(target)
    }
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
            scope: source.scope === "workspace" ? "workspace" : "global",
            workspaceTheme: typeof source.workspaceTheme === "string" ? source.workspaceTheme : "",
            workspaceWallpapers: source.workspaceWallpapers && typeof source.workspaceWallpapers === "object"
                && !Array.isArray(source.workspaceWallpapers) ? source.workspaceWallpapers : {},
            lastChangeEpoch: isFinite(epoch) ? epoch : 0,
            cycle: Array.isArray(source.cycle) ? source.cycle.slice() : [],
            cycleIndex: isFinite(index) ? index : 0,
            cycleTheme: typeof source.cycleTheme === "string" ? source.cycleTheme : ""
        }
    }
    function snapshot() {
        return {enabled: root.enabled, intervalMinutes: root.intervalMinutes, mode: root.mode,
            lastChangeEpoch: root.lastChangeEpoch, cycle: root.cycle, cycleIndex: root.cycleIndex,
            cycleTheme: root.cycleTheme, scope: root.scope, workspaceTheme: root.workspaceTheme,
            workspaceWallpapers: root.workspaceWallpapers}
    }
    function applyConfig(raw) {
        let parsed = {}
        try { parsed = raw && String(raw).trim() ? JSON.parse(raw) : {} }
        catch (error) { root.lastError = "Invalid auto-wallpaper.json: " + error }
        const config = root.normalize(parsed)
        if (config.enabled && config.lastChangeEpoch <= 0) config.lastChangeEpoch = Date.now()
        root.enabled = config.enabled
        root.intervalMinutes = config.intervalMinutes
        root.mode = config.mode
        root.scope = config.scope
        root.workspaceTheme = config.workspaceTheme
        root.workspaceWallpapers = config.workspaceWallpapers
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
    function cycleValid(list) {
        return root.cycleTheme === root.themeName && Array.isArray(root.cycle) && root.sameSet(root.cycle, list)
    }
    function pickNext() {
        const list = root.paths.slice()
        if (list.length <= 1) return {path: "", cycle: [], cycleIndex: 0, changed: false}
        if (!root.shuffle || root.perWorkspace) {
            const at = root.selectedWallpaper ? list.indexOf(root.selectedWallpaper) : -1
            const step = at >= 0 ? (at + 1) % list.length : 0
            return {path: list[step], cycle: [], cycleIndex: 0, changed: list[step] !== root.selectedWallpaper}
        }
        const valid = root.cycleValid(list)
        const order = valid ? root.cycle.slice() : root.shuffled(list)
        const at = valid ? (root.cycleIndex || 0) : (root.current ? order.indexOf(root.current) : -1)
        const step = (at + 1) % order.length
        return {path: order[step], cycle: order, cycleIndex: step, changed: order[step] !== root.current}
    }
    function elapsed() { return root.nowEpoch - Math.max(0, root.lastChangeEpoch) }
    function isDue() { return root.rotationEnabled && Math.max(0, root.elapsed()) >= root.intervalMinutes * 60000 }
    function minutesUntil() {
        if (!root.enabled) return -1
        return Math.ceil(Math.max(1, root.intervalMinutes * 60000 - root.elapsed()) / 60000)
    }

    function setEnabled(value) {
        if (root.perWorkspace) return
        root.lastError = ""
        root.save({enabled: value === true})
        if (value === true) Qt.callLater(root.applyNext)
        else root.lastAction = "Automatic switching disabled"
    }
    function updateSchedule(patch) { root.save(patch); root.lastAction = "Schedule saved" }
    function applyNext() {
        if (root.busy) return
        const next = root.pickNext()
        if (next.changed && next.path) {
            if (root.perWorkspace) root.setWallpaper(next.path)
            else root.switchTo(next.path, next, "")
            return
        }
        if (root.entries.length === 0) { root.lastAction = "No wallpapers for this theme"; root.refresh(); return }
        root.lastAction = "Already showing the only wallpaper"
        root.save({lastChangeEpoch: Date.now()})
    }
    function applyAdjacent(direction) {
        if (root.busy || root.paths.length === 0) return
        const at = root.paths.indexOf(root.selectedWallpaper)
        root.setWallpaper(root.paths[(Math.max(0, at) + direction + root.paths.length) % root.paths.length])
    }
    function setWallpaper(path) {
        if (root.busy || !path) return
        root.lastError = ""
        root.failedWallpapers = ({})
        if (!root.perWorkspace) { root.switchTo(path, null, ""); return }
        if (root.workspaceId <= 0) { root.lastError = "No active workspace."; return }
        const choices = Object.assign({}, root.workspaceTheme === root.themeName ? root.workspaceWallpapers : {})
        choices[String(root.workspaceId)] = path
        root.save({workspaceTheme: root.themeName, workspaceWallpapers: choices})
        root.lastAction = "Wallpaper saved for workspace " + root.workspaceName
    }
    function switchTo(path, next, output) {
        if (!path) { root.lastError = "No wallpaper selected."; return }
        root.pending = path
        root.pendingOutput = output
        root.pendingNext = next
        setProcess.command = output
            ? ["env", "WALLPAPER_WAIT_FOR_LOCK=1", root.libraryPath + "/wallpaper/wallpaper.awww.sh", path, output]
            : [root.libraryPath + "/wallpaper.sh", "set", path, "--global"]
        setProcess.running = true
    }
    function finishSwitch(code, error) {
        const applied = root.pending, output = root.pendingOutput
        if (code === 0) {
            if (output) root.appliedWallpapers = Object.assign({}, root.appliedWallpapers, {[output]: applied})
            else {
                root.current = applied
                const patch = {lastChangeEpoch: Date.now(), cycleTheme: root.themeName}
                if (root.pendingNext) { patch.cycle = root.pendingNext.cycle; patch.cycleIndex = root.pendingNext.cycleIndex }
                root.save(patch)
                root.lastAction = "Wallpaper set to " + root.wallpaperName(applied)
                root.lastError = ""
            }
        } else {
            if (output) root.failedWallpapers = Object.assign({}, root.failedWallpapers, {[output]: applied})
            root.lastError = String(error || "Wallpaper change failed").trim()
        }
        root.pending = ""
        root.pendingOutput = ""
        root.pendingNext = null
        Qt.callLater(root.reconcile)
    }
    function reconcile() {
        scheduleTimer.stop()
        root.nowEpoch = Date.now()
        if (!root.loaded || root.busy) return
        if (root.perWorkspace) {
            if (!root.themeKnown || root.entries.length === 0) return
            for (const target of root.workspaceTargets) {
                if (!target.path || root.appliedWallpapers[target.output] === target.path
                    || root.failedWallpapers[target.output] === target.path) continue
                root.switchTo(target.path, null, target.output)
                return
            }
            return
        }
        if (!root.rotationEnabled || root.lastError || root.entries.length === 0) return
        if (root.isDue()) root.applyNext()
        else scheduleTimer.start()
    }
    function applyTheme(name) {
        if (!name || name === root.themeName) return
        const known = root.themeKnown
        root.themeName = name
        root.themeKnown = true
        if (!known || !root.loaded) return
        root.entries = []
        root.appliedWallpapers = ({})
        root.save({lastChangeEpoch: Date.now(), cycle: [], cycleTheme: "", workspaceTheme: name, workspaceWallpapers: {}})
        root.lastAction = "Theme changed to " + name
        root.refresh(true)
    }

    function refresh(ensureThumbs) {
        if (ensureThumbs === true) { if (!cacheProcess.running) cacheProcess.running = true; return }
        if (!catalogProcess.running) catalogProcess.running = true
    }
    function updateCurrent() { if (!currentProcess.running) currentProcess.running = true }
    function loadCatalog(code, out, error) {
        if (code !== 0) { root.lastError = String(error || "Could not list wallpapers").trim(); return }
        let list = []
        try { list = JSON.parse(out) || [] }
        catch (parseError) { root.lastError = "Could not read the wallpaper catalog: " + parseError; return }
        const seen = {}, next = []
        for (const item of list) {
            const path = String(item.path || "").trim()
            if (!path || seen[path]) continue
            seen[path] = true
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
    property Process catalogProcess: Process {
        command: [root.libraryPath + "/wallpaper.sh", "json"]
        stdout: StdioCollector { id: catalogOut; waitForEnd: true }
        stderr: StdioCollector { id: catalogErr; waitForEnd: true }
        onExited: code => root.loadCatalog(code, catalogOut.text, catalogErr.text)
    }
    property Process currentProcess: Process {
        command: [root.libraryPath + "/wallpaper.sh", "get", "--global"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.current = String(text).trim().split("\n").pop() }
        onExited: Qt.callLater(root.reconcile)
    }
    property Process cacheProcess: Process {
        command: [root.libraryPath + "/wallpaper/wallpaper.cache.sh"]
        onExited: root.refresh()
    }
    property Process setProcess: Process {
        stderr: StdioCollector { id: setErr; waitForEnd: true }
        onExited: code => root.finishSwitch(code, setErr.text)
    }
    property Timer scheduleTimer: Timer {
        interval: Math.max(1, root.intervalMinutes * 60000 - root.elapsed())
        onTriggered: root.updateCurrent()
    }
    property IpcHandler ipc: IpcHandler {
        target: "wallpaper"
        function backendChanged(): void {
            root.appliedWallpapers = ({})
            root.failedWallpapers = ({})
            root.updateCurrent()
        }
        function next(): void { root.applyNext() }
        function scope(value: string): void { root.setScope(value) }
        function set(path: string): void { root.setWallpaper(path) }
        function enable(): void { root.setEnabled(true) }
        function disable(): void { root.setEnabled(false) }
        function toggle(): void { root.setEnabled(!root.enabled) }
        function status(): string {
            return "scope=" + root.scope + " workspace=" + root.workspaceName + " busy=" + root.busy
                + " enabled=" + root.rotationEnabled + " mode=" + root.mode + " interval=" + root.intervalMinutes
                + " theme=\"" + root.themeName + "\" count=" + root.entries.length
                + " current=\"" + root.wallpaperName(root.selectedWallpaper) + "\" next=\"" + root.nextText() + "\""
                + (root.lastError ? " error=\"" + root.lastError + "\"" : "")
        }
    }

    Component.onCompleted: {
        root.nowEpoch = Date.now()
        root.updateCurrent()
        root.refresh()
    }
}

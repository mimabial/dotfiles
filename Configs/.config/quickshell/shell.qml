//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

ShellRoot {
    id: shellRoot
    property string home: Quickshell.env("HOME")
    property string workflow: "default"
    property string themeName: ""
    property string layoutName: "main"
    property bool stateReady: false
    property string mode: workflow === "gaming" ? "hidden" : layoutName === "top" ? "top" : layoutName === "winbar" ? "winbar" : "main"
    property bool userHidden: false
    property string popupName: ""
    property var barLayout: []
    readonly property var barModules: (Array.isArray(barLayout) ? barLayout : Object.keys(barLayout || {}).reduce((all, key) => all.concat(barLayout[key] || []), [])).map(item => typeof item === "string" ? item : String(item.id || ""))
    readonly property bool dateModuleVisible: !userHidden && (barModules.includes("date") || barModules.includes("datetime") && (mode === "winbar" ? store.winbarClock % 4 < 3 : mode === "top" ? [0, 1, 4, 5, 6, 7].includes(store.topClock % 8) : store.mainClock % 4 === 2))
    readonly property bool clockModuleVisible: !userHidden && barModules.includes("datetime") && (mode === "winbar" || mode === "top" ? store.topClock % 8 !== 6 : store.mainClock % 4 !== 2)
    readonly property string timeVisibility: Quickshell.processId + " " + Number(dateModuleVisible) + " " + Number(clockModuleVisible) + "\n"
    property real volumeLimit: 1
    property real volumeMinDb: -60
    property real volumeMaxDb: 0
    property real volumeStepDb: 1
    property var timerItems: []
    property var stopwatch: ({elapsed: 0, started: 0, running: false, laps: []})
    property double timerNowMs: Date.now()
    readonly property int timerNow: Math.floor(timerNowMs / 1000)
    readonly property real stopwatchMs: Math.max(0, Number(stopwatch.elapsed) + (stopwatch.running ? timerNowMs - Number(stopwatch.started) : 0))
    readonly property var activeTimers: timerItems.filter(item => Number(item.epoch) > timerNow).sort((a, b) => a.epoch - b.epoch)
    property Theme style: Theme { home: shellRoot.home; layout: shellRoot.layoutName }
    readonly property var palette: style.palette
    readonly property color background: role("bg", "#1f2430")
    readonly property color foreground: role("fg", "#ffffff")
    readonly property color accent: role("accent", foreground)
    property string baseFont: "JetBrainsMono Nerd Font"
    property string userFont: ""
    readonly property string fontFamily: userFont || baseFont
    property string iconFont: "CaskaydiaCove Nerd Font"
    readonly property var fontFamilies: [fontFamily, iconFont, "Noto Color Emoji", "monospace"]
    readonly property real rounding: style.radius
    readonly property real moduleRadius: layoutName === "winbar" ? 0 : rounding
    readonly property real barOpacity: workflow === "powersaver" ? 1 : workflow === "windows" ? .5 : ["top", "winbar"].includes(layoutName) ? .4 : .6
    readonly property color barColor: store.barTransparent ? "transparent" : alpha(background, barOpacity)
    property SystemClock clock: SystemClock { precision: SystemClock.Minutes }
    readonly property alias store: persistent
    PersistentProperties {
        id: persistent
        property int topClock: 2
        property int mainClock: 3
        property bool mainDateNumeric: false
        property int winbarClock: 0
        property bool barTransparent: false
    }

    function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
    function mediaColor(output) {
        const classes = output && output.class ? [].concat(output.class) : [], map = { firefox: "c3", elisa: "c4", mpd: "c2", spotify: "c2", chromium: "c1", chrome: "c1", brave: "c1", vlc: "c5", mpv: "c5" }
        if (classes.includes("nothing-playing")) return alpha(role("c8", foreground), .4)
        if (classes.includes("stopped")) return alpha(role("c8", foreground), .6)
        const player = classes.find(name => map[name]); return alpha(role(map[player] || "accent", accent), player ? .85 : .7)
    }
    // true while a bar is priming keyboard focus for a freshly opened panel;
    // the focus grab clears during that transition and must not be read as a
    // click outside
    property bool focusPriming: false
    function run(command) { Quickshell.execDetached(command) }
    // PipeWire exposes PulseAudio's cubic scalar: dB = 60 log10(volume).
    function volumeToDb(value) { return 60 * Math.log10(value) }
    function dbToVolume(value) { return Math.pow(10, value / 60) }
    function setVolumeLimit(value, persist) { volumeLimit = Math.max(dbToVolume(volumeMinDb), Math.min(dbToVolume(volumeMaxDb), value)); if (persist) volumeLimitFile.setText(volumeLimit.toFixed(6) + "\n") }
    function refreshVolumeRange() { if (!volumeRangeProbe.running) volumeRangeProbe.running = true }
    function loadVolumeRange(raw) { try { const range = JSON.parse(raw), min = Number(range.minimum), max = Number(range.maximum), step = Number(range.step); if (isFinite(min) && isFinite(max) && isFinite(step) && min < max && step > 0) { volumeMinDb = min; volumeMaxDb = max; volumeStepDb = step; setVolumeLimit(volumeLimit, true) } } catch (error) {} }
    function loadTimers(raw) { try { timerItems = JSON.parse(raw) || [] } catch (error) { timerItems = [] } }
    function loadStopwatch(raw) { try { const saved = JSON.parse(raw); stopwatch = ({elapsed:Number(saved.elapsed)||0, started:Number(saved.started)||0, running:saved.running===true, laps:saved.laps||[]}) } catch (error) {} }
    function refreshTimers() { timerStateFile.reload() }
    function controlStopwatch(action) {
        const elapsed = stopwatchMs, running = stopwatch.running, laps = stopwatch.laps || []
        stopwatch = action === "reset" ? ({elapsed:0, started:0, running:false, laps:[]})
            : action === "lap" ? ({elapsed:stopwatch.elapsed, started:stopwatch.started, running:running, laps:laps.concat([elapsed])})
            : running ? ({elapsed:elapsed, started:0, running:false, laps:laps}) : ({elapsed:elapsed, started:Date.now(), running:true, laps:laps})
        timerNowMs = Date.now(); stopwatchStateFile.setText(JSON.stringify(stopwatch))
    }
    function togglePopup(name) { popupName = popupName === name ? "" : name }
    function closePopup() { popupName = "" }
    function toggleBarTransparency() { store.barTransparent = !store.barTransparent }
    function barLayoutIcon(name) { return ({winbar:"", top:"", left:"", sidebar:"", main:""})[name] || "" }
    function loadBarLayout(raw) { try { barLayout = JSON.parse(raw) } catch (error) { barLayout = [] } }
    function loadState(raw) {
        const text = String(raw)
        const modeMatch = text.match(/(?:^|\n)HYPR_WORKFLOW=["']?([^"'\n]+)/)
        const themeMatch = text.match(/(?:^|\n)HYPR_THEME=["']?([^"'\n]+)/)
        const layoutMatch = text.match(/(?:^|\n)WAYBAR_LAYOUT_NAME=["']?([^"'\n]+)/)
        workflow = modeMatch ? modeMatch[1].trim() : "default"
        themeName = themeMatch ? themeMatch[1].trim() : ""
        layoutName = layoutMatch ? layoutMatch[1].trim() : "main"
        stateReady = true
    }
    function color(value) {
        if (typeof value !== "string") return value
        const hex = value.slice(1)
        return Qt.rgba(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, hex.length > 6 ? parseInt(hex.slice(6, 8), 16) / 255 : 1)
    }
    function role(name, fallback) { return color(palette[name] || fallback) }
    function loadFont(raw, user) {
        const icon = String(raw).match(/BAR_ICON_FONT\s*=\s*"([^"]+)"/)
        if (icon) iconFont = icon[1]
        const match = String(raw).match(/vars\.set\("BAR_FONT",\s*"([^"]+)"\)|BAR_FONT\s*=\s*"([^"]+)"/)
        if (user) userFont = match ? match[1] : ""
        else if (match) baseFont = match[1] || match[2]
    }
    function refresh() {
        stateFile.reload()
        layoutFile.reload()
        baseFontFile.reload()
        userFontFile.reload()
    }

    FileView {
        id: stateFile
        path: shellRoot.home + "/.local/state/hypr/staterc"
        watchChanges: true
        onLoaded: shellRoot.loadState(text())
        onFileChanged: reload()
    }
    FileView { id: layoutFile; path: shellRoot.home + "/.config/quickshell/layouts/" + shellRoot.layoutName + ".json"; watchChanges: true; printErrors: false; onPathChanged: reload(); onLoaded: shellRoot.loadBarLayout(text()); onFileChanged: reload() }
    FileView {
        id: baseFontFile
        path: shellRoot.home + "/.config/hypr/vars.lua"
        watchChanges: true
        onLoaded: shellRoot.loadFont(text(), false)
        onFileChanged: reload()
    }
    FileView {
        id: userFontFile
        path: shellRoot.home + "/.config/hypr/userfonts.lua"
        watchChanges: true
        printErrors: false
        onLoaded: shellRoot.loadFont(text(), true)
        onFileChanged: reload()
    }
    FileView { id: volumeLimitFile; path: shellRoot.home + "/.local/state/quickshell/volume-limit"; printErrors: false; onLoaded: { const value = Number(text()); if (value > 0) shellRoot.setVolumeLimit(value, false) } }
    FileView { id: timerStateFile; path: shellRoot.home + "/.local/state/quickshell/timers.json"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadTimers(text()); onFileChanged: reload() }
    FileView { id: stopwatchStateFile; path: shellRoot.home + "/.local/state/quickshell/stopwatch.json"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadStopwatch(text()); onFileChanged: reload() }
    FileView { id: timeVisibilityFile; path: shellRoot.home + "/.local/state/quickshell/time-visibility"; printErrors: false }
    Timer { id: timeVisibilityWrite; interval: 0; running: true; onTriggered: timeVisibilityFile.setText(shellRoot.timeVisibility) }
    Timer { interval: shellRoot.stopwatch.running && shellRoot.popupName === "timer" ? 100 : 1000; repeat: true; running: shellRoot.activeTimers.length > 0 || shellRoot.stopwatch.running; triggeredOnStart: true; onTriggered: shellRoot.timerNowMs = Date.now() }
    Process { id: volumeRangeProbe; command: [shellRoot.home + "/.local/lib/hypr/controls/volume-control.sh", "--limits"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.loadVolumeRange(text) } }
    Process { command: [shellRoot.home + "/.local/lib/hypr/calendar/alarm-timer.sh", "restore"]; running: true }
    ReloadToast { shell: shellRoot }

    onModeChanged: closePopup()
    onLayoutNameChanged: { barLayout = []; layoutFile.reload() }
    onUserHiddenChanged: if (userHidden) closePopup()
    onTimeVisibilityChanged: timeVisibilityWrite.restart()

    IpcHandler {
        target: "bar"
        function toggle(): void { shellRoot.userHidden = !shellRoot.userHidden }
        function show(): void { shellRoot.userHidden = false }
        function reveal(): void { shellRoot.userHidden = false }
        function hide(): void { shellRoot.userHidden = true }
        function refresh(): void { shellRoot.refresh() }
        function reload(): void { Quickshell.reload(false) }
        function popup(name: string): void { shellRoot.togglePopup(name) }
        function transparency(): void { shellRoot.toggleBarTransparency() }
        function popupName(): string { return shellRoot.popupName }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "main" ? Quickshell.screens : []
        delegate: Component { MainBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "winbar" ? Quickshell.screens : []
        delegate: Component { WinBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "top" ? Quickshell.screens : []
        delegate: Component { TopBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
}

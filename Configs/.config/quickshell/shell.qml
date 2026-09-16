//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

ShellRoot {
    id: shellRoot
    property string home: Quickshell.env("HOME")
    property string workflow: "default"
    property string themeName: ""
    property string layoutName: "right"
    property string sunsetEnabled: ""
    property bool keepAwakeManual: false
    property bool keepAwakeAudio: true
    property string indicatorRefreshTarget: "all"
    property int indicatorRefreshSerial: 0
    property bool powerProfileRestorePending: false
    property bool stateReady: false
    property string mode: workflow === "gaming" ? "hidden" : String(barLayout.panel || "")
    property bool userHidden: false
    property string popupName: ""
    property var barLayout: ({})
    readonly property var barModules: ["modules", "left", "center", "right"].reduce((all, key) => all.concat(Array.isArray(barLayout[key]) ? barLayout[key] : []), []).map(item => typeof item === "string" ? item : String(item.id || ""))
    readonly property bool dateModuleVisible: !userHidden && (barModules.includes("date") || barModules.includes("datetime") && (mode === "winbar" ? store.winbarClock % 4 < 3 : mode === "horizontal" ? [0, 1, 4, 5, 6, 7].includes(store.topClock % 8) : store.mainClock % 4 === 2))
    readonly property bool clockModuleVisible: !userHidden && barModules.includes("datetime") && (mode === "winbar" || mode === "horizontal" ? store.topClock % 8 !== 6 : store.mainClock % 4 !== 2)
    readonly property string timeVisibility: Quickshell.processId + " " + Number(dateModuleVisible) + " " + Number(clockModuleVisible) + "\n"
    property real volumeLimit: 1
    property real volumeMinDb: -60
    property real volumeMaxDb: 0
    property real volumeStepDb: 1
    property var timerItems: []
    property double timerNowMs: Date.now()
    readonly property int timerNow: Math.floor(timerNowMs / 1000)
    readonly property var activeEntries: timerItems.filter(item => Number(item.epoch) > timerNow).sort((a, b) => a.epoch - b.epoch)
    readonly property var activeTimers: activeEntries.filter(item => item.kind === "timer")
    readonly property var activeAlarms: activeEntries.filter(item => item.kind === "alarm")
    readonly property alias clockwork: clockworkState
    readonly property var monitorPreviewCoordinator: monitorPreviewGuardLoader.item
    property Theme style: Theme { home: shellRoot.home; layout: shellRoot.layoutName }
    readonly property var palette: style.palette
    readonly property color background: role("bg", "#1f2430")
    readonly property color foreground: role("fg", "#ffffff")
    readonly property color accent: role("accent", foreground)
    readonly property color urgent: role("error", "#f38ba8")
    property string baseFont: "JetBrainsMono Nerd Font"
    property string userFont: ""
    property string themeFont: ""
    // same precedence hyprland.lua loads them in: userfonts beats the theme pack,
    // the theme pack beats the vars default
    readonly property string fontFamily: userFont || themeFont || baseFont
    // a theme font carrying no Nerd Font glyphs needs a companion face for icons,
    // or they resolve through fontconfig to whatever proportional face it picks.
    // Miracode is Monocraft's vector reinterpretation, so Monocraft's icons share
    // its skeleton and cell width. Any font not listed keeps the default.
    readonly property var iconFonts: ({
        "Miracode": "Monocraft"
    })
    property string iconFontOverride: ""
    // a patched theme font already has the glyphs, and its own Mono twin matches
    // the text's drawing style; the pinned face is only for fonts that ship neither
    readonly property string iconFont: iconFontOverride || iconFonts[fontFamily]
        || (Qt.fontFamilies().includes(fontFamily + " Mono") ? fontFamily : "CaskaydiaCove Nerd Font")
    // hypr's vars.lua owns the terminal choice; this is only the pre-load default
    property string terminal: "foot"
    // Nerd Font ships double-width icon glyphs with a single-cell advance, and Qt
    // centres on the advance, so the ink hangs off to the right. The Mono faces
    // squeeze them into one cell, making ink and advance agree.
    readonly property string iconGlyphFont: {
        const mono = iconFont + " Mono"
        return Qt.fontFamilies().includes(mono) ? mono : iconFont
    }
    // A Mono face sizes its icons to the cell while text is sized by cap height,
    // and the two are unrelated in every font, so swapping the theme font changes
    // how large the icons read beside it. Measuring beats tabulating: the median
    // of these five glyphs tracks the median of the whole icon set to within
    // 0.002em on every face installed here, so the ratio needs no per-font entry.
    TextMetrics { id: capProbe; font.family: shellRoot.fontFamily; font.pixelSize: 200; text: "M" }
    TextMetrics { id: inkProbe0; font.family: shellRoot.iconGlyphFont; font.pixelSize: 200; text: "" }
    TextMetrics { id: inkProbe1; font.family: shellRoot.iconGlyphFont; font.pixelSize: 200; text: "" }
    TextMetrics { id: inkProbe2; font.family: shellRoot.iconGlyphFont; font.pixelSize: 200; text: "" }
    TextMetrics { id: inkProbe3; font.family: shellRoot.iconGlyphFont; font.pixelSize: 200; text: "" }
    TextMetrics { id: inkProbe4; font.family: shellRoot.iconGlyphFont; font.pixelSize: 200; text: "" }
    readonly property real iconCapRatio: {
        const cap = capProbe.tightBoundingRect.height
        const ink = [inkProbe0, inkProbe1, inkProbe2, inkProbe3, inkProbe4]
            .map(probe => probe.tightBoundingRect.height).filter(height => height > 0).sort((a, b) => a - b)
        return cap > 0 && ink.length ? cap / ink[Math.floor(ink.length / 2)] : 1
    }
    // Ink equal to cap height reads as a smaller icon: a letter carries the eye on
    // its stems, a pictogram spreads the same height over a box. Taste, not
    // measurement — the one number here meant to be tuned by eye.
    property real iconOpticalBoost: 1.20
    readonly property real iconFontScale: iconCapRatio * iconOpticalBoost
    readonly property real rounding: style.radius
    // unscaled: the card's frame has to read as the same weight as the frames on
    // the windows behind it, and Hyprland draws those in raw pixels
    readonly property real borderWidth: style.border
    readonly property real moduleRadius: mode === "winbar" ? 0 : rounding
    readonly property string barEdge: String(barLayout.edge || "right")
    readonly property real barOpacity: workflow === "powersaver" ? 1 : workflow === "windows" ? .5 : mode === "vertical" ? .6 : .4
    readonly property color barColor: store.barTransparent ? "transparent" : alpha(background, barOpacity)
    property SystemClock clock: SystemClock { precision: SystemClock.Minutes }
    readonly property alias store: persistent
    readonly property var exposeDefaults: ({
        previewPlacement: "in-place", windowFooterStyle: "floating",
        animationStyle: "original", animationTimings: ({}), slideDirection: ({}),
        backgroundBlur: 4, backgroundDim: 6, hotCornerEnabled: true,
        hotCornerPosition: "top-left", moveCursorToWindow: true,
        multiMonitorMode: "mirrored", showFooter: true
    })
    property var exposeConfig: Object.assign({}, exposeDefaults)
    PersistentProperties {
        id: persistent
        property int topClock: 2
        property int mainClock: 3
        property bool mainDateNumeric: false
        property int winbarClock: 0
        property bool barTransparent: false
        property bool barBlur: true
        property string sudokuDifficulty: "easy"
        property int sudokuBestEasy: 0
        property int sudokuBestMedium: 0
        property int sudokuBestHard: 0
        property int clockworkWorkMinutes: 25
        property int clockworkShortBreakMinutes: 5
        property int clockworkCycles: 4
        property int clockworkLongBreakMinutes: 15
        property bool clockworkSound: true
        property string clockworkBreakColor: "#a6e3a1"
        property string bluetoothAudioPolicies: "{}"
        property string webcamDevice: ""
    }

    ClockworkState { id: clockworkState; shell: shellRoot }

    function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
    function loadExposeConfig(raw) {
        try {
            const value = JSON.parse(String(raw))
            exposeConfig = value && typeof value === "object"
                ? Object.assign({}, exposeDefaults, value) : Object.assign({}, exposeDefaults)
        } catch (error) {
            console.warn("expose settings: " + error)
            exposeConfig = Object.assign({}, exposeDefaults)
        }
    }
    function updateExposeSetting(name, value) {
        const next = Object.assign({}, exposeConfig)
        next[name] = value
        exposeConfig = next
        exposeSettingsFile.setText(JSON.stringify(next, null, 2) + "\n")
    }
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
    property var popupCard: null
    property var mediaPopup: null
    function run(command) { Quickshell.execDetached(command) }
    function refreshIndicators(target) {
        indicatorRefreshTarget = String(target || "all")
        ++indicatorRefreshSerial
    }
    function restorePowerProfile() {
        if (powerProfileRestore.running) {
            powerProfileRestorePending = true
            return
        }
        powerProfileRestore.command = ["hyprshell", "system/powerprofiles", "--restore"]
        powerProfileRestore.running = true
    }
    // PipeWire exposes PulseAudio's cubic scalar: dB = 60 log10(volume).
    function volumeToDb(value) { return 60 * Math.log10(value) }
    function dbToVolume(value) { return Math.pow(10, value / 60) }
    function setVolumeLimit(value, persist) { volumeLimit = Math.max(dbToVolume(volumeMinDb), Math.min(dbToVolume(volumeMaxDb), value)); if (persist) volumeLimitFile.setText(volumeLimit.toFixed(6) + "\n") }
    function refreshVolumeRange() { if (!volumeRangeProbe.running) volumeRangeProbe.running = true }
    function loadVolumeRange(raw) { try { const range = JSON.parse(raw), min = Number(range.minimum), max = Number(range.maximum), step = Number(range.step); if (isFinite(min) && isFinite(max) && isFinite(step) && min < max && step > 0) { volumeMinDb = min; volumeMaxDb = max; volumeStepDb = step; setVolumeLimit(volumeLimit, true) } } catch (error) {} }
    function duration(seconds) { const minutes = Math.round(seconds / 60); return minutes > 59 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m" }
    function profileName(profile) { return PowerProfile.toString(profile).replace(/([a-z])([A-Z])/g, "$1 $2") }
    function loadTimers(raw) { try { timerItems = JSON.parse(raw) || [] } catch (error) { timerItems = [] } }
    function refreshTimers() { timerStateFile.reload() }
    // a popup opened by name (keybind, menutree) centers on the screen; a click
    // on a bar module keeps its popup anchored to the button it came from
    property string popupCenteredName: ""
    function togglePopup(name, centered) { popupCenteredName = centered === true ? name : ""; popupName = popupName === name ? "" : name }
    function closePopup() { popupName = "" }
    function toggleBarTransparency() { store.barTransparent = !store.barTransparent }
    function toggleBarBlur() { store.barBlur = !store.barBlur }
    function barLayoutIcon() { return ({top:"", bottom:"", left:"", right:""})[barEdge] || "" }
    function loadBarLayout(raw) {
        try {
            const data = JSON.parse(raw), edges = data.panel === "vertical" ? ["left", "right"] : ["top", "bottom"]
            if (!["vertical", "horizontal", "winbar"].includes(data.panel) || !edges.includes(data.edge)) throw new Error("invalid panel or edge")
            barLayout = data
        } catch (error) { console.warn("layout " + layoutName + ": " + error); barLayout = ({}) }
    }
    function loadState(raw) {
        const text = String(raw)
        const modeMatch = text.match(/(?:^|\n)HYPR_WORKFLOW=["']?([^"'\n]+)/)
        const themeMatch = text.match(/(?:^|\n)HYPR_THEME=["']?([^"'\n]+)/)
        const layoutMatch = text.match(/(?:^|\n)QUICKSHELL_LAYOUT_NAME=["']?([^"'\n]+)/)
        const sunsetMatch = text.match(/(?:^|\n)HYPRSUNSET_ENABLED=["']?([^"'\n]+)/)
        const keepAwakeMatch = text.match(/(?:^|\n)HYPR_KEEP_AWAKE=["']?([^"'\n]+)/)
        const keepAwakeAudioMatch = text.match(/(?:^|\n)HYPR_KEEP_AWAKE_AUDIO=["']?([^"'\n]+)/)
        workflow = modeMatch ? modeMatch[1].trim() : "default"
        themeName = themeMatch ? themeMatch[1].trim() : ""
        layoutName = layoutMatch ? layoutMatch[1].trim() : "right"
        sunsetEnabled = sunsetMatch ? sunsetMatch[1].trim() : ""
        keepAwakeManual = keepAwakeMatch ? keepAwakeMatch[1].trim() === "1" : false
        keepAwakeAudio = keepAwakeAudioMatch ? keepAwakeAudioMatch[1].trim() !== "0" : true
        stateReady = true
    }
    function color(value) {
        if (typeof value !== "string") return value
        const hex = value.slice(1)
        return Qt.rgba(parseInt(hex.slice(0, 2), 16) / 255, parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, hex.length > 6 ? parseInt(hex.slice(6, 8), 16) / 255 : 1)
    }
    function role(name, fallback) { return color(palette[name] || fallback) }
    // one hover recipe for every popup surface; `strength` scales the Style base
    // so an emphasised row stays a ratio of the plain one instead of a literal
    function hoverFill(strength) { return alpha(role("hvr_bg", accent), Style.hoverFillAlpha * (strength === undefined ? 1 : strength)) }
    function hoverEdge(strength) { return alpha(role("hvr_br", foreground), Style.hoverBorderAlpha * (strength === undefined ? 1 : strength)) }
    function loadFont(raw, key) {
        const icon = String(raw).match(/vars\.set\("BAR_ICON_FONT",\s*"([^"]+)"\)|BAR_ICON_FONT\s*=\s*"([^"]+)"/)
        if (icon) iconFontOverride = icon[1] || icon[2]
        const term = String(raw).match(/vars\.set\("TERMINAL",\s*"([^"]+)"\)|TERMINAL\s*=\s*"([^"]+)"/)
        if (term) terminal = term[1] || term[2]
        const match = String(raw).match(/vars\.set\("BAR_FONT",\s*"([^"]+)"\)|BAR_FONT\s*=\s*"([^"]+)"/)
        if (key === "baseFont") { if (match) baseFont = match[1] || match[2] }
        else shellRoot[key] = match ? (match[1] || match[2]) : ""
    }
    function refresh() {
        stateFile.reload()
        layoutFile.reload()
        baseFontFile.reload()
        themeFontFile.reload()
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
        onLoaded: shellRoot.loadFont(text(), "baseFont")
        onFileChanged: reload()
    }
    FileView { id: themeFontFile; path: shellRoot.home + "/.config/hypr/themes/theme.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadFont(text(), "themeFont"); onFileChanged: reload() }
    FileView {
        id: userFontFile
        path: shellRoot.home + "/.config/hypr/userfonts.lua"
        watchChanges: true
        printErrors: false
        onLoaded: shellRoot.loadFont(text(), "userFont")
        onFileChanged: reload()
    }
    FileView { id: volumeLimitFile; path: shellRoot.home + "/.local/state/quickshell/volume-limit"; printErrors: false; onLoaded: { const value = Number(text()); if (value > 0) shellRoot.setVolumeLimit(value, false) } }
    FileView { id: timerStateFile; path: shellRoot.home + "/.local/state/quickshell/timers.json"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadTimers(text()); onFileChanged: reload() }
    FileView { id: exposeSettingsFile; path: shellRoot.home + "/.config/quickshell/expose/settings.json"; watchChanges: true; onLoaded: shellRoot.loadExposeConfig(text()); onFileChanged: reload() }
    FileView { id: timeVisibilityFile; path: shellRoot.home + "/.local/state/quickshell/time-visibility"; printErrors: false }
    Timer { id: timeVisibilityWrite; interval: 0; running: true; onTriggered: timeVisibilityFile.setText(shellRoot.timeVisibility) }
    Timer { interval: 1000; repeat: true; running: shellRoot.activeEntries.length > 0; triggeredOnStart: true; onTriggered: shellRoot.timerNowMs = Date.now() }
    Process { id: volumeRangeProbe; command: [shellRoot.home + "/.local/lib/hypr/controls/volume-control.sh", "--limits"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.loadVolumeRange(text) } }
    Process {
        id: powerProfileRestore
        onExited: {
            if (shellRoot.powerProfileRestorePending) {
                shellRoot.powerProfileRestorePending = false
                shellRoot.restorePowerProfile()
            }
        }
    }
    Process { command: [shellRoot.home + "/.local/lib/hypr/calendar/alarm-timer.sh", "restore"]; running: true }
    ReloadToast { shell: shellRoot }
    // The three heaviest subtrees in the config and none of them is on screen at
    // startup. Loading by url keeps their compile off the path to the first bar,
    // and setSource passes shell as an initial property because each wires the
    // Commons singletons from its own Component.onCompleted — a later assignment
    // would let them publish a null shell first.
    Loader {
        id: overviewLoader
        asynchronous: true
        Component.onCompleted: overviewLoader.setSource(Qt.resolvedUrl("expose/Overview.qml"), { shell: shellRoot })
    }
    Loader {
        id: dockLoader
        asynchronous: true
        Component.onCompleted: dockLoader.setSource(Qt.resolvedUrl("dock/Dock.qml"), { shell: shellRoot })
    }
    // The guard adopts any preview the display daemon reports, including one it
    // did not start, so it must end up loaded rather than wait for a first use.
    Loader {
        id: monitorPreviewGuardLoader
        asynchronous: true
        Component.onCompleted: monitorPreviewGuardLoader.setSource(Qt.resolvedUrl("monitor/DisplayPreviewGuard.qml"), { shell: shellRoot })
    }
    // A popup is an xdg child of the bar's layer surface, so a blur rule on that
    // surface blurs the popup's whole area too — well past the bar. The
    // threshold confines it to what is actually painted: the bar at barOpacity
    // and the popup card at its own, but not the empty margin around either.
    LayerBlur { surface: "hypr-shell-bar"; enabled: shellRoot.store.barBlur; ignoreAlpha: 0.1 }

    onModeChanged: closePopup()
    onLayoutNameChanged: { barLayout = ({}); layoutFile.reload() }
    onUserHiddenChanged: if (userHidden) closePopup()
    onTimeVisibilityChanged: timeVisibilityWrite.restart()
    Component.onCompleted: restorePowerProfile()

    Connections {
        target: UPower
        function onOnBatteryChanged() { shellRoot.restorePowerProfile() }
    }

    IpcHandler {
        target: "bar"
        function toggle(): void { shellRoot.userHidden = !shellRoot.userHidden }
        function show(): void { shellRoot.userHidden = false }
        function reveal(): void { shellRoot.userHidden = false }
        function hide(): void { shellRoot.userHidden = true }
        function refresh(): void { shellRoot.refresh() }
        function reload(): void { Quickshell.reload(false) }
        // the soft reload keeps live instances, so it misses a changed vars.lua
        // value or a re-evaluated font.family; this is the one to verify against
        function reloadHard(): void { Quickshell.reload(true) }
        function popup(name: string): void { shellRoot.togglePopup(name, true) }
        function bookmarks(): void { shellRoot.togglePopup("bookmarks", true) }
        function transparency(): void { shellRoot.toggleBarTransparency() }
        function blur(): void { shellRoot.toggleBarBlur() }
        function popupName(): string { return shellRoot.popupName }
    }
    IpcHandler {
        target: "indicators"
        function refresh(target: string): void { shellRoot.refreshIndicators(target) }
    }
    IpcHandler {
        target: "crmne.mpris"
        function status(): string { return JSON.stringify(Media.statusObject()) }
        function playPause(): string { return Media.playPause() ? "ok" : "unhandled" }
        function previous(): string { return Media.previous() ? "ok" : "unhandled" }
        function next(): string { return Media.next() ? "ok" : "unhandled" }
        function raise(): string { return Media.raisePlayer() ? "ok" : "unhandled" }
    }
    IpcHandler {
        target: "cliamp"
        function open(): void { shellRoot.mediaPopup?.showPopup() }
        function close(): void { shellRoot.mediaPopup?.hidePopup() }
        function show(): void { shellRoot.mediaPopup?.showPopup() }
        function hide(): void { shellRoot.mediaPopup?.hidePopup() }
        function toggle(): void { shellRoot.mediaPopup?.togglePopup() }
        function refresh(): void { shellRoot.mediaPopup?.refresh() }
        function play(): void { shellRoot.mediaPopup?.play() }
        function pause(): void { shellRoot.mediaPopup?.pause() }
        function stop(): void { shellRoot.mediaPopup?.stop() }
        function next(): void { shellRoot.mediaPopup?.nextTrack() }
        function prev(): void { shellRoot.mediaPopup?.prevTrack() }
        function playUrl(url: string): void { shellRoot.mediaPopup?.playUrl(url) }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "vertical" ? Quickshell.screens : []
        delegate: Component { MainBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "winbar" ? Quickshell.screens : []
        delegate: Component { WinBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
    Variants {
        model: shellRoot.stateReady && shellRoot.mode === "horizontal" ? Quickshell.screens : []
        delegate: Component { TopBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
}

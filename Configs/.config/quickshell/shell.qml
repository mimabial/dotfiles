pragma ComponentBehavior: Bound

//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.systemstats
import "ClockFormats.js" as ClockFormats
import "Opacity.js" as Opacity

ShellRoot {
    id: shellRoot
    property string home: Quickshell.env("HOME")
    property string lockviewScreen: ""
    property string sessionMenuScreen: ""
    property string workflow: "default"
    property string themeName: ""
    property string layoutName: "top"
    property string sunsetEnabled: ""
    property bool keepAwakeManual: false
    property bool keepAwakeAudio: true
    property bool keepAwakeFullscreen: false
    property bool notificationsPaused: false
    property string animation: "default"
    property string colorSource: "theme"
    property string colorMode: ""
    property string windowLayout: ""
    property bool caffeineFullscreenActive: false
    property bool caffeineGameActive: false
    property string indicatorRefreshTarget: "all"
    property int indicatorRefreshSerial: 0
    property bool powerProfileRestorePending: false
    property bool stateReady: false
    property string mode: workflow === "gaming" ? "hidden" : style.ready ? String(barLayout.panel || "") : ""
    property bool userHidden: false
    property bool barRevealed: false
    readonly property bool barShown: (mode === "horizontal" || mode === "winbar") && !userHidden
        && (mode !== "winbar" || !prefs.winbarAutoHide || barRevealed || popupName !== "")
    property string popupName: ""
    property var menuBarHeadings: []
    property string dragKey: ""
    property var barLayout: ({})
    property var layoutData: ({})
    readonly property var barSections: ["left", "center", "right", "tray"]
    function moduleIds(sections) {
        const entries = sections.reduce((allEntries, section) =>
            allEntries.concat(Array.isArray(barLayout[section]) ? barLayout[section] : []), [])
        return entries.map(entry => typeof entry === "string" ? entry : String(entry.id || ""))
    }
    readonly property var barModules: moduleIds(barSections)
    // the tray's modules exist only while its flyout is open
    property bool trayOpen: false
    signal trayToggleRequested
    readonly property var liveModules: moduleIds(trayOpen ? barSections : barSections.filter(section => section !== "tray"))
    readonly property var trayHidden: parseTrayList(prefs.trayHidden)
    readonly property var trayPinned: parseTrayList(prefs.trayPinned)
    function parseTrayList(raw) {
        try { const value = JSON.parse(raw); return Array.isArray(value) ? value : [] }
        catch (error) { return [] }
    }
    function trayKey(section, entry) {
        const id = typeof entry === "string" ? entry : String(entry.id || "")
        const instance = typeof entry === "string" || entry.trayInstance == null ? "" : String(entry.trayInstance)
        return layoutName + ":" + section + ":" + id + (instance ? ":instance:" + instance : "")
    }
    function parseTrayKey(key) {
        const parts = key.split(":")
        return { section: parts[1], entryId: parts.slice(2).join(":") }
    }
    function ensureUniqueTrayInstances(layout) {
        if (layout.panel !== "winbar") return false
        let assignedInstances = false
        for (const section of barSections) {
            if (!Array.isArray(layout[section])) continue
            const seenKeys = new Set()
            const usedInstances = new Set(layout[section].filter(entry => typeof entry === "object" && entry && entry.trayInstance != null)
                .map(entry => String(entry.trayInstance)))
            let nextInstanceNumber = 1
            for (let index = 0; index < layout[section].length; index++) {
                let entry = layout[section][index]
                let moduleKey = trayKey(section, entry)
                if (seenKeys.has(moduleKey)) {
                    let instance
                    do { instance = "auto-" + nextInstanceNumber++ } while (usedInstances.has(instance))
                    usedInstances.add(instance)
                    entry = typeof entry === "string" ? { id: entry, trayInstance: instance }
                        : Object.assign({}, entry, { trayInstance: instance })
                    layout[section][index] = entry
                    moduleKey = trayKey(section, entry)
                    assignedInstances = true
                }
                seenKeys.add(moduleKey)
            }
        }
        return assignedInstances
    }
    function saveMovedBarLayout(layout) {
        const output = JSON.stringify(layout, null, 2) + "\n"
        if (layoutData.extends) { loadSharedLayout(output); sharedLayoutFile.setText(output) }
        else { layoutData = layout; barLayout = layout; layoutFile.setText(output) }
    }
    function moveBarModule(sourceKey, destinationSection, targetKey, afterTarget, restorePosition) {
        if (!barModules.includes("tray") || !barSections.includes(destinationSection) || targetKey === sourceKey) return
        const source = parseTrayKey(sourceKey)
        const editableLayout = JSON.parse(layoutData.extends ? sharedLayoutFile.text() : JSON.stringify(layoutData))
        const sourceIndex = (editableLayout[source.section] || []).findIndex(entry => trayKey(source.section, entry) === sourceKey)
        if (sourceIndex < 0 && !source.entryId.startsWith("icon:")) return
        let movingEntry = sourceIndex < 0 ? source.entryId : editableLayout[source.section].splice(sourceIndex, 1)[0]
        const position = movingEntry.trayPosition
        const hiddenPositions = (editableLayout.tray || []).map(entry => entry.trayPosition)
            .filter(saved => saved?.section === (restorePosition && position ? position.section : source.section))
        if (destinationSection === "tray" && source.section !== "tray") {
            let index = sourceIndex
            for (const saved of hiddenPositions.sort((a, b) => a.index - b.index))
                if (saved.index <= index) index++
            movingEntry = Object.assign(typeof movingEntry === "string" ? { id: movingEntry } : movingEntry,
                { trayPosition: { section: source.section, index, stringEntry: typeof movingEntry === "string" } })
        } else if (source.section === "tray" && destinationSection !== "tray" && position) {
            movingEntry = Object.assign({}, movingEntry)
            delete movingEntry.trayPosition
            if (position.stringEntry && Object.keys(movingEntry).length === 1) movingEntry = movingEntry.id
            if (restorePosition) destinationSection = position.section
        }
        editableLayout[destinationSection] = editableLayout[destinationSection] || []
        const destinationEntries = editableLayout[destinationSection]
        let insertionIndex = destinationEntries.findIndex(entry => trayKey(destinationSection, entry) === targetKey)
        if (insertionIndex < 0) insertionIndex = destinationEntries.length
        else if (afterTarget) insertionIndex++
        if (restorePosition && position)
            insertionIndex = Math.max(0, Math.min(destinationEntries.length, position.index - hiddenPositions.filter(saved => saved.index < position.index).length))
        destinationEntries.splice(insertionIndex, 0, movingEntry)
        ensureUniqueTrayInstances(editableLayout)
        saveMovedBarLayout(editableLayout)
    }
    function toggleTrayIcon(id) {
        prefs.trayHidden = JSON.stringify(trayHidden.includes(id) ? trayHidden.filter(item => item !== id) : trayHidden.concat(id))
    }
    function toggleTrayPin(id) {
        prefs.trayPinned = JSON.stringify(trayPinned.includes(id) ? trayPinned.filter(item => item !== id) : trayPinned.concat(id))
    }
    readonly property string clockKind: barLayout.clock || (mode === "winbar" ? (prefs.winbarSmall ? "winbarSmall" : "winbar") : "top")
    readonly property var selectedClockFormat: ClockFormats.selected(clockKind, prefs[clockKind + "Clock"])
    readonly property bool clockOnBar: !userHidden && ["datetime", "notification-center", "gnome-date-menu"].some(id => barModules.includes(id))
    readonly property bool dateModuleVisible: clockOnBar && selectedClockFormat.hasDate
    readonly property bool clockModuleVisible: clockOnBar && selectedClockFormat.hasTime
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
    readonly property alias clockwork: clockworkState
    readonly property alias bitwarden: bitwardenVault
    readonly property alias systemStats: systemStatsService
    readonly property var wallpaper: Wallpaper
    readonly property var monitorPreviewCoordinator: monitorPreviewGuardLoader.item
    readonly property var dock: dockLoader.item
    readonly property var expose: overviewLoader.item
    property Theme style: Theme { home: shellRoot.home; styleName: String(shellRoot.barLayout.style || shellRoot.layoutName); variant: shellRoot.prefs.winbarSmall ? "small" : "" }
    readonly property var palette: style.palette
    readonly property color background: role("bg", "#1f2430")
    readonly property color foreground: role("fg", "#ffffff")
    readonly property color accent: role("accent", foreground)
    readonly property color urgent: role("error", "#f38ba8")
    readonly property color mutedText: alpha(foreground, Style.mutedTextAlpha)
    readonly property color faintText: alpha(foreground, Style.faintTextAlpha)
    property var hyprVarLayers: ({})
    readonly property var hyprVarLoadOrder: ["vars", "userVars", "theme", "userfonts", "userprefs"]
    readonly property string fontFamily: style.box("shell").fontFamily ?? hyprVar("BAR_FONT", "JetBrainsMono Nerd Font")
    // a theme font carrying no Nerd Font glyphs needs a companion face for icons,
    // or they resolve through fontconfig to whatever proportional face it picks.
    // The companion must match the theme font's cell width (Monoid and Miracode
    // are both 0.667em). Any font not listed keeps the default.
    readonly property var iconFonts: ({
        "Miracode": "Monoid Nerd Font"
    })
    // a patched theme font already has the glyphs, and its own Mono twin matches
    // the text's drawing style; the pinned face is only for fonts that ship neither
    readonly property string iconFont: hyprVar("BAR_ICON_FONT", "") || iconFonts[fontFamily]
        || (Qt.fontFamilies().includes(fontFamily + " Mono") ? fontFamily : "CaskaydiaCove Nerd Font")
    readonly property string terminal: hyprVar("TERMINAL", "alacritty")
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
    readonly property real rounding: style.box("shell").rounding === undefined ? style.radius : Style.px(style.box("shell").rounding)
    // unscaled: the card's frame has to read as the same weight as the frames on
    // the windows behind it, and Hyprland draws those in raw pixels
    readonly property real borderWidth: style.overrides.shell?.borderWidth ?? style.border
    property real windowBorderWidth: style.border
    readonly property real moduleRadius: mode === "winbar" ? 0 : rounding
    readonly property string barEdge: String((barLayout.panel === "winbar" && prefs.winbarEdge) || barLayout.edge || "top")
    property real barFloatGap: Style.popupGap
    readonly property real barOpacity: style.box("shell").barOpacity ?? (prefs.barOpacity >= 0 ? prefs.barOpacity : workflow === "powersaver" || workflow === "gnome" ? 1 : workflow === "windows" ? .5 : .4)
    readonly property bool barBlur: style.box("shell").barBlur ?? prefs.barBlur
    readonly property color barColor: styleColor(style.box("bar." + barEdge).backgroundColor, alpha(background, barOpacity))
    property SystemClock clock: SystemClock { precision: SystemClock.Minutes }
    readonly property alias store: persistent
    readonly property alias prefs: prefsAdapter
    FileView {
        path: shellRoot.home + "/.local/state/quickshell/bar.json"
        blockLoading: true
        printErrors: false
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: prefsAdapter
            property int topClock: 2
            property int winbarClock: 0
            property int winbarSmallClock: 0
            property int macosClock: 0
            property int gnomeClock: 0
            property bool barBlur: true
            property real barOpacity: -1
            property bool barFloating: false
            property bool winbarAutoHide: false
            property string winbarCombine: "always"
            property bool winbarSmall: false
            property bool winbarWeatherBadge: false
            property string winbarEdge: ""
            property bool winbarHighlightLabels: false
            property bool winbarLimitLabels: false
            property string trayHidden: "[]"
            property string trayPinned: "[]"
            property bool trayShowIcons: true
        }
    }
    readonly property var exposeDefaults: ({
        previewPlacement: "in-place", windowFooterStyle: "floating",
        animationStyle: "original", animationTimings: ({}), slideDirection: ({}),
        backgroundBlur: 4, backgroundDim: 6, hotCornerEnabled: true,
        hotCornerPosition: "top-left", hotCornerDelay: 0,
        initialWorkspaceScope: "all", workspaceLabelStyle: "full",
        moveCursorToWindow: true,
        multiMonitorMode: "mirrored", showFooter: true
    })
    property var exposeConfig: Object.assign({}, exposeDefaults)
    PersistentProperties {
        id: persistent
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
        property int lyricsDelayTenths: 0
        property int lyricsFontStep: 0
    }

    ClockworkState { id: clockworkState; shell: shellRoot }
    Bitwarden { id: bitwardenVault; shell: shellRoot }
    SystemStatsService { id: systemStatsService; shell: shellRoot }

    function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
    function styleColor(spec, fallback) { return !spec ? fallback : Array.isArray(spec) ? alpha(role(spec[0], fallback), spec[1] ?? 1) : role(spec, fallback) }
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
    // true while a bar is priming keyboard focus for a freshly opened panel;
    // the focus grab clears during that transition and must not be read as a
    // click outside
    property bool focusPriming: false
    property var popupCard: null
    function switchPopup(direction) {
        if (!popupCard) return
        const window = popupCard.anchorWindow, buttons = []
        function collect(item) {
            for (const child of item.children) {
                if (!child.visible || !child.enabled) continue
                const button = child as BarButton
                if (button && button.hasPopup && !("popupsAllowed" in button && !button.popupsAllowed)
                    && !("popupEnabled" in button && !button.popupEnabled)) buttons.push(button)
                else collect(child)
            }
        }
        collect(window.contentItem)
        const vertical = popupCard.position !== "top" && popupCard.position !== "bottom"
        buttons.sort((a, b) => {
            const first = a.mapToItem(window.contentItem, 0, 0), second = b.mapToItem(window.contentItem, 0, 0)
            return vertical ? first.y - second.y : first.x - second.x
        })
        const index = buttons.indexOf(popupCard.anchorItem)
        if (buttons.length > 1) buttons[index < 0 ? direction > 0 ? 0 : buttons.length - 1 : (index + direction + buttons.length) % buttons.length].clicked(Qt.LeftButton)
    }
    property var mediaPopup: null
    function run(command, onExited) {
        if (!onExited) return Quickshell.execDetached(command)
        const process = exitWatcher.createObject(shellRoot, { command: ["setsid", "-fw"].concat(command) })
        process.exited.connect(() => { onExited(); process.destroy() })
        process.running = true
    }
    Component { id: exitWatcher; Process {} }
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
    function setVolumeLimit(value, persist) {
        volumeLimit = Math.max(dbToVolume(volumeMinDb), Math.min(dbToVolume(volumeMaxDb), value))
        if (persist) volumeLimitFile.setText(volumeLimit.toFixed(6) + "\n")
    }
    function refreshVolumeRange() { if (!volumeRangeProbe.running) volumeRangeProbe.running = true }
    function loadVolumeRange(raw) {
        try {
            const range = JSON.parse(raw)
            const minimum = Number(range.minimum), maximum = Number(range.maximum), step = Number(range.step)
            if (!isFinite(minimum) || !isFinite(maximum) || !isFinite(step) || minimum >= maximum || step <= 0) return
            volumeMinDb = minimum; volumeMaxDb = maximum; volumeStepDb = step
            setVolumeLimit(volumeLimit, true)
        } catch (error) {}
    }
    function duration(seconds) { const minutes = Math.round(seconds / 60); return minutes > 59 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m" }
    function profileName(profile) { return PowerProfile.toString(profile).replace(/([a-z])([A-Z])/g, "$1 $2") }
    function loadTimers(raw) { try { timerItems = JSON.parse(raw) || [] } catch (error) { timerItems = [] } }
    function refreshTimers() { timerStateFile.reload() }
    // a popup opened by name (keybind, menutree) centers on the screen; a click
    // on a bar module keeps its popup anchored to the button it came from
    property string popupCenteredName: ""
    function togglePopup(name, centered) { popupCenteredName = centered === true ? name : ""; popupName = popupName === name ? "" : name }
    function closePopup() { popupName = "" }
    function toggleWinbarCombine() { prefs.winbarCombine = prefs.winbarCombine === "never" ? "always" : "never" }
    function switchMenu(step) {
        const names = ["hyprmenu"].concat(menuBarHeadings.map(title => "appmenu:" + title))
        const index = names.indexOf(popupName)
        if (index < 0) return
        popupCenteredName = ""
        popupName = names[(index + step + names.length) % names.length]
    }
    function toggleBarBlur() { prefs.barBlur = !prefs.barBlur }
    function toggleBarFloating() { prefs.barFloating = !prefs.barFloating }
    function refreshWindowMetrics() { if (!windowMetricsProbe.running) windowMetricsProbe.running = true }
    function refreshMenuState() { refreshWindowMetrics(); if (!pausedProbe.running) pausedProbe.running = true }
    function menuTargetActive(target) {
        const toggles = {
            style_bar_blur: prefs.barBlur, style_bar_floating: prefs.barFloating,
            style_dock_blur: !!dock?.blurred,
            trigger_toggle_nightlight: sunsetEnabled === "1", trigger_toggle_keep_awake: keepAwakeManual,
            trigger_toggle_notifications: !notificationsPaused, trigger_toggle_bar: !userHidden, trigger_toggle_window_gaps: barFloatGap > 0
        }
        const choices = {
            style_bar_layout_: layoutName, style_workflow_: workflow, style_animations_: animation, style_text_size_: Style.textSize,
            style_color_mode_source_: colorSource, style_color_mode_: colorMode, trigger_toggle_workspace_layout_: windowLayout,
            style_bar_opacity_: Opacity.presetId(prefs.barOpacity), style_dock_opacity_: dock ? Opacity.presetId(dock.dockOpacity) : null,
            setup_power_profile_: PowerProfile.toString(PowerProfiles.profile).replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase(),
            style_expose_hot_corner_: exposeConfig.hotCornerEnabled ? exposeConfig.hotCornerPosition : null
        }
        const prefix = Object.keys(choices).find(prefix => target.startsWith(prefix))
        return toggles[target] ?? (prefix === undefined ? undefined : target === prefix + choices[prefix])
    }
    function loadWindowMetrics(raw) {
        for (const chunk of String(raw).split(/\n\s*\n/)) try {
            const data = JSON.parse(chunk)
            if (data.option === "general:gaps_out") {
                const gap = parseFloat(String(data.css || "").trim().split(/\s+/)[0])
                if (isFinite(gap)) barFloatGap = Math.max(0, gap)
            } else if (data.option === "general:border_size" && typeof data.int === "number") windowBorderWidth = data.int
        } catch (error) {}
    }
    function barLayoutIcon() { return ({top:"", bottom:""})[barEdge] || "" }
    function setBarLayout(data) {
        if (!["horizontal", "winbar"].includes(data.panel) || !["top", "bottom"].includes(data.edge)) throw new Error("invalid panel or edge")
        barLayout = data
    }
    function loadBarLayout(raw) {
        try {
            const data = JSON.parse(raw)
            const assignedInstances = ensureUniqueTrayInstances(data)
            layoutData = data
            if (layoutData.extends) { barLayout = ({}); sharedLayoutFile.reload() }
            else setBarLayout(layoutData)
            if (assignedInstances) layoutFile.setText(JSON.stringify(data, null, 2) + "\n")
        } catch (error) { console.warn("layout " + layoutName + ": " + error); barLayout = ({}) }
    }
    function loadSharedLayout(raw) {
        if (!layoutData.extends) return
        try {
            const merged = Object.assign({}, JSON.parse(raw), layoutData)
            for (const section of ["left", "center", "right"])
                if (Array.isArray(layoutData[section + "Prepend"]))
                    merged[section] = layoutData[section + "Prepend"].concat(merged[section] || [])
            setBarLayout(merged)
        }
        catch (error) { console.warn("layout " + layoutName + ": " + error); barLayout = ({}) }
    }
    function loadState(raw) {
        const text = String(raw)
        const value = (key, fallback) => (text.match(new RegExp(`(?:^|\n)${key}=["']?([^"'\n]+)`))?.[1] ?? fallback).trim()
        workflow = value("HYPR_WORKFLOW", "default")
        themeName = value("HYPR_THEME", "")
        layoutName = value("QUICKSHELL_LAYOUT_NAME", "top")
        sunsetEnabled = value("HYPRSUNSET_ENABLED", "")
        keepAwakeManual = value("HYPR_KEEP_AWAKE", "0") === "1"
        keepAwakeAudio = value("HYPR_KEEP_AWAKE_AUDIO", "1") !== "0"
        keepAwakeFullscreen = value("HYPR_KEEP_AWAKE_FULLSCREEN", "0") === "1"
        animation = value("HYPR_ANIMATION", "default")
        colorSource = value("selected_color_source", "theme")
        colorMode = ({ 1: "auto", 2: "dark", 3: "light" })[value("selected_color_mode", "2")] ?? ""
        stateReady = true
    }
    function loadCaffeineWindowState(raw) {
        const state = String(raw).trim().split(/\s+/)
        caffeineFullscreenActive = state[0] === "1"
        caffeineGameActive = state[1] === "1"
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
    function selectedFill() { return alpha(role("act_bg", accent), Style.selectedFillAlpha) }
    function selectedEdge() { return alpha(role("act_br", accent), Style.selectedBorderAlpha) }
    function hyprVar(name, fallback) {
        let value = fallback
        for (const layer of hyprVarLoadOrder) value = hyprVarLayers[layer]?.[name] || value
        return value
    }
    function loadHyprVars(layer, raw) {
        const assignment = /vars\.set\("([\w.]+)",\s*"([^"]*)"\)|^\s*(?:\["([\w.]+)"\]|(\w+))\s*=\s*"([^"]*)",?\s*$/gm
        const values = {}
        for (let match = assignment.exec(raw); match; match = assignment.exec(raw))
            values[match[1] || match[3] || match[4]] = match[2] ?? match[5]
        hyprVarLayers = Object.assign({}, hyprVarLayers, { [layer]: values })
    }
    function refresh() {
        stateFile.reload()
        layoutFile.reload()
        varsFile.reload()
        userVarsFile.reload()
        themeVarsFile.reload()
        userFontsFile.reload()
        userPrefsFile.reload()
    }

    FileView {
        id: stateFile
        path: shellRoot.home + "/.local/state/hypr/staterc"
        watchChanges: true
        onLoaded: shellRoot.loadState(text())
        onFileChanged: reload()
    }
    FileView { path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/caffeine-windows"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadCaffeineWindowState(text()); onFileChanged: reload() }
    FileView { path: shellRoot.home + "/.local/state/hypr/window-layout.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.windowLayout = String(text()).match(/layout\s*=\s*["']([^"']+)/)?.[1] ?? ""; onFileChanged: reload() }
    FileView { id: layoutFile; path: shellRoot.home + "/.config/quickshell/layouts/" + shellRoot.layoutName + ".json"; watchChanges: true; atomicWrites: true; blockWrites: true; printErrors: false; onPathChanged: reload(); onLoaded: shellRoot.loadBarLayout(text()); onFileChanged: reload() }
    FileView { id: sharedLayoutFile; path: shellRoot.layoutData.extends ? shellRoot.home + "/.config/quickshell/layouts/shared/" + shellRoot.layoutData.extends + ".json" : ""; watchChanges: true; atomicWrites: true; blockWrites: true; printErrors: false; onLoaded: shellRoot.loadSharedLayout(text()); onFileChanged: reload() }
    FileView { id: varsFile; path: shellRoot.home + "/.local/share/hypr/vars.lua"; watchChanges: true; onLoaded: shellRoot.loadHyprVars("vars", text()); onFileChanged: reload() }
    FileView { id: userVarsFile; path: shellRoot.home + "/.config/hypr/vars.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadHyprVars("userVars", text()); onFileChanged: reload() }
    FileView { id: themeVarsFile; path: shellRoot.home + "/.config/hypr/themes/theme.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadHyprVars("theme", text()); onFileChanged: reload() }
    FileView { id: userFontsFile; path: shellRoot.home + "/.config/hypr/userfonts.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadHyprVars("userfonts", text()); onFileChanged: reload() }
    FileView { id: userPrefsFile; path: shellRoot.home + "/.config/hypr/userprefs.lua"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadHyprVars("userprefs", text()); onFileChanged: reload() }
    FileView { id: volumeLimitFile; path: shellRoot.home + "/.local/state/quickshell/volume-limit"; printErrors: false; onLoaded: { const value = Number(text()); if (value > 0) shellRoot.setVolumeLimit(value, false) } }
    FileView { id: timerStateFile; path: shellRoot.home + "/.local/state/quickshell/timers.json"; watchChanges: true; printErrors: false; onLoaded: shellRoot.loadTimers(text()); onFileChanged: reload() }
    FileView { id: exposeSettingsFile; path: shellRoot.home + "/.config/quickshell/expose/settings.json"; watchChanges: true; onLoaded: shellRoot.loadExposeConfig(text()); onFileChanged: reload() }
    FileView { id: timeVisibilityFile; path: shellRoot.home + "/.local/state/quickshell/time-visibility"; printErrors: false }
    Timer { id: timeVisibilityWrite; interval: 0; running: true; onTriggered: timeVisibilityFile.setText(shellRoot.timeVisibility) }
    Timer { interval: 1000; repeat: true; running: shellRoot.activeEntries.length > 0; triggeredOnStart: true; onTriggered: shellRoot.timerNowMs = Date.now() }
    Process { id: volumeRangeProbe; command: [shellRoot.home + "/.local/lib/hypr/controls/volume-control.sh", "--limits"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.loadVolumeRange(text) } }
    Process { id: windowMetricsProbe; command: ["hyprctl", "-j", "--batch", "getoption general:gaps_out ; getoption general:border_size"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.loadWindowMetrics(text) } }
    Process { id: pausedProbe; command: ["dunstctl", "is-paused"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: shellRoot.notificationsPaused = text.trim() === "true" } }
    Process {
        id: powerProfileRestore
        onRunningChanged: if (!running) {
            if (shellRoot.powerProfileRestorePending) {
                shellRoot.powerProfileRestorePending = false
                shellRoot.restorePowerProfile()
            }
        }
    }
    Process { command: [shellRoot.home + "/.local/lib/hypr/calendar/alarm-timer.sh", "restore"]; running: true }
    ReloadToast { shell: shellRoot }
    AltGrHints { shell: shellRoot }
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
    Loader {
        id: lockviewLoader
        asynchronous: true
        active: shellRoot.lockviewScreen !== ""
        Component.onCompleted: lockviewLoader.setSource(Qt.resolvedUrl("lockview/LockView.qml"), { shell: shellRoot })
    }
    LazyLoader {
        active: shellRoot.sessionMenuScreen !== ""
        SessionMenu { shell: shellRoot }
    }
    LayerBlur { surface: "hypr-shell-bar"; enabled: shellRoot.barBlur; ignoreAlpha: 0.1 }
    LayerBlur { surface: "hypr-shell-reload"; enabled: shellRoot.barBlur; ignoreAlpha: 0.1 }

    onModeChanged: closePopup()
    onLayoutNameChanged: { barRevealed = false; layoutData = ({}); barLayout = ({}); layoutFile.reload() }
    onUserHiddenChanged: if (userHidden) barRevealed = false
    onBarShownChanged: if (!barShown) closePopup()
    onTimeVisibilityChanged: timeVisibilityWrite.restart()
    Component.onCompleted: { restorePowerProfile(); refreshWindowMetrics() }

    Connections {
        target: UPower
        function onOnBatteryChanged() { shellRoot.restorePowerProfile() }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event && event.name === "configreloaded") shellRoot.refreshWindowMetrics() }
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
        function tray(): void { shellRoot.trayToggleRequested() }
        function menuBar(): void { if (shellRoot.layoutName === "macos") shellRoot.togglePopup("hyprmenu") }
        function bookmarks(): void { shellRoot.togglePopup("bookmarks", true) }
        function blur(): void { shellRoot.toggleBarBlur() }
        function opacity(percent: string): void { shellRoot.prefs.barOpacity = percent === "auto" ? -1 : Number(percent) / 100 }
        function floating(): void { shellRoot.toggleBarFloating() }
        function winbarEdge(edge: string): void { shellRoot.prefs.winbarEdge = edge }
        function floatingState(): string { return JSON.stringify({ enabled: shellRoot.prefs.barFloating, gap: shellRoot.barFloatGap }) }
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
        function lyrics(): void { shellRoot.mediaPopup?.showLyrics() }
        function refresh(): void { shellRoot.mediaPopup?.refresh() }
        function play(): void { shellRoot.mediaPopup?.play() }
        function pause(): void { shellRoot.mediaPopup?.pause() }
        function stop(): void { shellRoot.mediaPopup?.stop() }
        function next(): void { shellRoot.mediaPopup?.nextTrack() }
        function prev(): void { shellRoot.mediaPopup?.prevTrack() }
        function playUrl(url: string): void { shellRoot.mediaPopup?.playUrl(url) }
    }
    IpcHandler {
        id: lockviewIpc
        target: "lockview"
        function open(): void { shellRoot.lockviewScreen = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name }
        function close(): void { shellRoot.lockviewScreen = "" }
        function toggle(): void { if (shellRoot.lockviewScreen) lockviewIpc.close(); else lockviewIpc.open() }
    }
    IpcHandler {
        target: "sessionmenu"
        function toggle(): void { shellRoot.sessionMenuScreen = shellRoot.sessionMenuScreen ? "" : Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name }
    }
    Variants {
        model: shellRoot.stateReady && (shellRoot.mode === "horizontal" || shellRoot.mode === "winbar") ? Quickshell.screens : []
        delegate: Component { HorizontalBar { required property var modelData; shell: shellRoot; screen: modelData } }
    }
    Variants {
        model: shellRoot.mode === "winbar" && shellRoot.prefs.winbarAutoHide && !shellRoot.barShown && !shellRoot.userHidden ? Quickshell.screens : []
        delegate: Component {
            PanelWindow {
                required property var modelData
                screen: modelData
                anchors.left: true; anchors.right: true; anchors.bottom: true
                implicitHeight: Style.xs
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "hypr-shell-bar-reveal"
                WlrLayershell.layer: WlrLayer.Top
                Item {
                    anchors.fill: parent
                    HoverHandler { onHoveredChanged: if (hovered) shellRoot.barRevealed = true }
                }
            }
        }
    }
}

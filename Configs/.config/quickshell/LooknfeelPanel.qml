pragma ComponentBehavior: Bound
import QtQml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "LooknfeelSchema.js" as Schema
import "LooknfeelLua.js" as LuaConfig

// A GUI for the visual half of the Hyprland config: read current values, preview
// live while adjusting, and persist per theme.
//
// Its own layershell surface rather than a bar popup, because ~50 rows across 12
// sections needs a two-pane window. It still respects the one-global-popup rule
// by closing any open bar popup when it opens.
//
// Read paths and the storage contract are documented in LOOKNFEEL.md.
Scope {
    id: root

    required property var shell
    property bool opened: false
    property bool exclusivePhase: false

    // Current effective values, keyed by option: {value, type, set}.
    property var current: ({})
    // the theme pack's own values, so "back to default" means the theme's value
    // and not merely the value this panel happened to open with
    property var themeDefaults: ({})
    property var variableDefaults: ({})
    // Keys this panel owns. Absent means "the theme's value stands".
    property var overrides: ({})
    property var variableOverrides: ({})
    property var baselineAnimations: []
    property real speedMultiplier: 1
    property string engine: "master"
    property string variant: "dark"
    property int sectionIndex: 0
    property int rowIndex: 0
    property string errorText: ""
    property var pipelineOptions: ({})
    property var pipelineCurrent: ({})
    property string pipelinePendingId: ""
    property var pipelinePendingValue: null
    property bool cursorPersistPending: false
    property bool cursorPreviewPending: false
    property bool cursorSyncPending: false

    readonly property string stateDir: root.shell.home + "/.local/state/hypr"
    readonly property string libDir: root.shell.home + "/.local/lib/hypr"

    // Lua patterns are ASCII-only; looknfeel.lua slugs identically so the panel
    // writes where the resolver reads.
    function slug(name) {
        return String(name || "default").toLowerCase()
            .replace(/[^a-z0-9]+/g, "-").replace(/^-+/, "").replace(/-+$/, "")
    }

    readonly property string themeKey: root.slug(root.shell.themeName) + "." + root.variant
    readonly property string overridePath: root.stateDir + "/looknfeel.d/" + root.themeKey + ".lua"

    // The Layout section shows only the active engine's knobs. Every engine's
    // keys resolve regardless of general:layout, so this is presentation only.
    readonly property var sections: {
        var base = Schema.sections()
        var out = []
        for (var i = 0; i < base.length; i++) {
            var rows = base[i].rows
            if (base[i].title === "Layout") rows = rows.concat(Schema.layoutRows(root.engine))
            out.push({ title: base[i].title, rows: rows })
        }
        return out
    }

    readonly property var activeRows: root.sections[root.sectionIndex]
        ? root.sections[root.sectionIndex].rows : []

    // ------------------------------------------------------------ lifecycle

    function open() {
        if (root.shell && typeof root.shell.closePopup === "function")
            root.shell.closePopup()
        root.opened = true
        root.errorText = ""
        root.exclusivePhase = true
        focusPrime.restart()
        root.refresh()
        keyCatcher.forceActiveFocus()
    }

    function close() {
        // The preview is already live, so a pending edit has to reach the file
        // rather than evaporating at the next reload.
        if (persistTimer.running) {
            persistTimer.stop()
            root.persist()
        }
        root.opened = false
    }

    function toggle() {
        if (root.opened) root.close()
        else root.open()
    }

    Timer { id: focusPrime; interval: 150; onTriggered: root.exclusivePhase = false }

    // -------------------------------------------------------------- reading

    function refresh() {
        var keys = Schema.queryKeys()
        var batch = []
        for (var i = 0; i < keys.length; i++) batch.push("getoption " + keys[i])
        var engines = ["dwindle", "master", "scrolling"]
        for (var e = 0; e < engines.length; e++) {
            var rows = Schema.layoutRows(engines[e])
            for (var r = 0; r < rows.length; r++) batch.push("getoption " + rows[r].key)
        }
        optionReader.command = ["hyprctl", "-j", "--batch", batch.join(" ; ")]
        optionReader.running = true

        blockReader.command = ["lua", root.libDir + "/window/looknfeel-read.lua", root.overridePath]
        blockReader.running = true

        baselineReader.command = ["lua", root.libDir + "/window/looknfeel-read.lua",
                                  root.stateDir + "/animations.lua"]
        baselineReader.running = true
    }

    Process {
        id: optionReader
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.current = LuaConfig.parseGetoption(text)
                var layout = root.current["general:layout"]
                if (layout && layout.value) root.engine = String(layout.value)
            }
        }
    }

    Process {
        id: blockReader
        // A missing file is the normal case for a theme with no overrides yet;
        // the reader exits non-zero on it, which is not an error here.
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var parsed = LuaConfig.parseRecords(text)
                root.overrides = parsed.keys
                root.variableOverrides = parsed.variables
                root.speedMultiplier = root.deriveMultiplier(parsed.animations)
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.overrides = ({})
                root.variableOverrides = ({})
                root.speedMultiplier = 1
            }
        }
    }

    Process {
        id: baselineReader
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.baselineAnimations = LuaConfig.parseRecords(text).animations
        }
    }

    // The multiplier is stored implicitly: scaled speeds are what land in the
    // file, so it is recovered by comparing against the active preset.
    function deriveMultiplier(written) {
        if (!written || written.length === 0) return 1
        for (var i = 0; i < root.baselineAnimations.length; i++) {
            var base = root.baselineAnimations[i]
            for (var j = 0; j < written.length; j++) {
                if (written[j].leaf === base.leaf && base.speed > 0)
                    return Math.round((written[j].speed / base.speed) * 100) / 100
            }
        }
        return 1
    }

    // ------------------------------------------------------------- pipelines

    readonly property var listedRows: {
        var out = []
        var base = Schema.sections()
        for (var i = 0; i < base.length; i++) {
            for (var j = 0; j < base[i].rows.length; j++) {
                if (base[i].rows[j].list) out.push(base[i].rows[j])
            }
        }
        return out
    }

    // Instantiator rather than Repeater: Repeater only creates Items, and these
    // delegates are Processes.
    Instantiator {
        model: root.listedRows
        delegate: Process {
            id: listProc
            required property var modelData
            command: [root.shell.home + "/.local/bin/hyprshell"].concat(modelData.list)
            running: root.opened
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                    var names = []
                    var lines = String(text).split("\n")
                    for (var i = 0; i < lines.length; i++) {
                        if (!lines[i]) continue
                        names.push(lines[i].split("\t")[0])
                    }
                    var next = Object.assign({}, root.pipelineOptions)
                    next[listProc.modelData.id] = names
                    root.pipelineOptions = next
                }
            }
        }
    }

    Process {
        id: pipelineSetter
        onExited: code => { if (code === 0) pipelineState.reload(); else root.pipelinePendingId = "" }
    }

    function setPipeline(row, name) {
        root.pipelinePendingValue = name
        root.pipelinePendingId = row.id
        pipelineSetter.command =
            [root.shell.home + "/.local/bin/hyprshell"].concat(row.set).concat([name])
        pipelineSetter.running = true
    }

    FileView {
        path: root.shell.home + "/.config/hypr/themes/theme.lua"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.themeDefaults = LuaConfig.parseThemeConfig(text())
            root.variableDefaults = LuaConfig.parseThemeVariables(text())
        }
    }

    FileView {
        id: pipelineState
        path: root.stateDir + "/staterc"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            var raw = String(text())
            var animation = raw.match(/(?:^|\n)HYPR_ANIMATION=["']?([^"'\n]+)/)
            var shader = raw.match(/(?:^|\n)HYPR_SHADER=["']?([^"'\n]+)/)
            var workflow = raw.match(/(?:^|\n)HYPR_WORKFLOW=["']?([^"'\n]+)/)
            var next = {
                animation_preset: animation ? animation[1] : "default",
                shader: shader ? shader[1] : "neutral",
                workflow: workflow ? workflow[1] : "default"
            }
            root.pipelineCurrent = next
            if (!pipelineSetter.running && root.pipelinePendingId !== ""
                    && String(next[root.pipelinePendingId]) === String(root.pipelinePendingValue))
                root.pipelinePendingId = ""
        }
    }

    FileView {
        path: root.stateDir + "/color_variant"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.variant = String(text()).trim() === "light" ? "light" : "dark"
    }

    // -------------------------------------------------------------- writing

    function valueFor(row) {
        if (row.type === "pipeline") return row.id === root.pipelinePendingId ? root.pipelinePendingValue : root.pipelineCurrent[row.id]
        if (row.id === "animation_speed") return root.speedMultiplier
        if (row.variable) {
            if (row.variable in root.variableOverrides)
                return root.variableOverrides[row.variable]
            return row.variable in root.variableDefaults
                ? root.variableDefaults[row.variable] : null
        }
        if (row.key in root.overrides) return root.overrides[row.key]
        var live = root.current[row.key]
        return live ? live.value : null
    }

    function isOverridden(row) {
        if (row.id === "animation_speed") return root.speedMultiplier !== 1
        if (row.type === "pipeline") return false
        if (row.variable) return row.variable in root.variableOverrides
        return row.key in root.overrides
    }

    function renderCurrent() {
        var animations = []
        if (root.speedMultiplier !== 1) {
            for (var i = 0; i < root.baselineAnimations.length; i++) {
                var leaf = root.baselineAnimations[i]
                animations.push({
                    leaf: leaf.leaf,
                    enabled: leaf.enabled,
                    speed: Math.max(0.1, Math.round(leaf.speed * root.speedMultiplier * 100) / 100),
                    bezier: leaf.bezier,
                    style: leaf.style
                })
            }
        }
        return LuaConfig.renderBlock(root.overrides, animations, root.variableOverrides)
    }

    // Dialling a row back to what the theme asks for is the same as resetting it,
    // so drop the key rather than emitting Lua that restates the theme. The theme
    // file is the reference; the live read is the fallback for keys it leaves to
    // Hyprland's own defaults.
    function baselineFor(row) {
        if (row.variable)
            return row.variable in root.variableDefaults
                ? root.variableDefaults[row.variable] : null
        if (row.key in root.themeDefaults) return root.themeDefaults[row.key]
        var live = root.current[row.key]
        return live && live.value !== undefined ? live.value : null
    }

    function matchesBaseline(row, value) {
        var baseline = root.baselineFor(row)
        if (baseline === undefined || baseline === null) return false
        if (row.type === "bool") return Boolean(baseline) === Boolean(value)
        if (row.type === "int" || row.type === "float") return Math.abs(Number(baseline) - Number(value)) < 1e-6
        return String(baseline) === String(value)
    }

    function setOverride(row, value) {
        if (row.variable) {
            var variableNext = Object.assign({}, root.variableOverrides)
            if (row.type === "int") value = Math.round(value)
            if (root.matchesBaseline(row, value)) delete variableNext[row.variable]
            else variableNext[row.variable] = String(value)
            root.variableOverrides = variableNext
            root.cursorPersistPending = true
            root.queueCursorPreview()
            root.applyPreview()
            return
        }
        var next = Object.assign({}, root.overrides)
        if (row.type === "int") value = Math.round(value)
        if (root.matchesBaseline(row, value)) delete next[row.key]
        else next[row.key] = value
        root.overrides = next
        root.applyPreview()
    }

    // Reset drops the key so the emitted Lua disappears and the theme's value
    // returns on reload. No default is ever stored.
    function resetRow(row) {
        if (row.id === "animation_speed") {
            root.speedMultiplier = 1
        } else if (row.variable) {
            var variableNext = Object.assign({}, root.variableOverrides)
            delete variableNext[row.variable]
            root.variableOverrides = variableNext
            root.cursorPersistPending = true
            root.queueCursorPreview()
        } else if (row.type !== "pipeline") {
            var next = Object.assign({}, root.overrides)
            delete next[row.key]
            root.overrides = next
        }
        root.applyPreview()
        if (!row.variable) reloadDebounce.restart()
    }

    function applyPreview() {
        var block = root.renderCurrent()
        if (block !== "") {
            // The separator matters: the block opens with a fence comment and
            // hyprctl parses a leading `--` as a flag.
            preview.command = ["hyprctl", "eval", "--", block]
            preview.running = true
        }
        persistTimer.restart()
    }

    Process { id: preview }
    Timer {
        id: cursorPreviewTimer
        interval: 40
        onTriggered: root.startCursorPreview()
    }
    Process {
        id: cursorPreview
        onExited: {
            if (root.cursorPreviewPending) cursorPreviewTimer.restart()
        }
    }
    Timer { id: persistTimer; interval: 250; onTriggered: root.persist() }
    // A cleared key only comes back on reload, since eval cannot un-set one.
    Timer { id: reloadDebounce; interval: 300; onTriggered: { reloader.running = true } }
    Process { id: reloader; command: ["hyprctl", "reload"] }

    function cursorValue(name) {
        if (name in root.variableOverrides) return root.variableOverrides[name]
        return name in root.variableDefaults ? root.variableDefaults[name] : ""
    }

    function queueCursorPreview() {
        root.cursorPreviewPending = true
        cursorPreviewTimer.restart()
    }

    function startCursorPreview() {
        if (cursorPreview.running) return
        var theme = String(root.cursorValue("CURSOR_THEME"))
        var size = Math.round(Number(root.cursorValue("CURSOR_SIZE")))
        if (theme === "" || isNaN(size) || size <= 0) return
        root.cursorPreviewPending = false
        cursorPreview.command = ["hyprctl", "setcursor", theme, String(size)]
        cursorPreview.running = true
    }

    function queueCursorSync() {
        root.cursorSyncPending = true
        cursorSyncTimer.restart()
    }

    function startCursorSync() {
        if (cursorSync.running) return
        root.cursorSyncPending = false
        cursorSync.running = true
    }

    Timer { id: cursorSyncTimer; interval: 700; onTriggered: root.startCursorSync() }
    Process {
        id: cursorSync
        command: [root.shell.home + "/.local/bin/hyprshell",
                  "theme/desktop.sync.sh", "--full", "--quiet"]
        onExited: code => {
            if (code !== 0) root.errorText = "could not sync cursor settings"
            else if (root.errorText === "could not sync cursor settings") root.errorText = ""
            if (root.cursorSyncPending) cursorSyncTimer.restart()
        }
    }

    function persist() {
        var block = root.renderCurrent()
        writer.syncCursor = root.cursorPersistPending
        root.cursorPersistPending = false
        if (block === "") {
            writer.command = ["sh", "-c", 'rm -f "$1"', "sh", root.overridePath]
        } else {
            writer.command = ["sh", "-c",
                'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1.new" && mv -f "$1.new" "$1"',
                "sh", root.overridePath, block]
        }
        writer.running = true
    }

    Process {
        id: writer
        property bool syncCursor: false
        onExited: code => {
            if (code !== 0) root.errorText = "could not write " + root.overridePath
            else {
                errorCheck.running = true
                if (writer.syncCursor) root.queueCursorSync()
            }
        }
    }

    Process {
        id: errorCheck
        command: ["hyprctl", "configerrors"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var message = String(text).trim()
                root.errorText = (message === "" || message === "no errors") ? "" : message
            }
        }
    }

    // ------------------------------------------------------------ interaction

    function adjust(row, direction) {
        if (row.type === "bool") { root.toggleRow(row); return }
        if (row.type === "enum") { root.cycle(row, direction); return }
        if (row.type === "pipeline") { root.cycle(row, direction); return }

        var step = row.step === undefined || row.step === 0 ? 1 : row.step
        var value = Number(root.valueFor(row))
        if (isNaN(value)) value = row.min
        value = Math.min(row.max, Math.max(row.min, value + step * direction))
        value = Math.round(value * 1000) / 1000

        if (row.id === "animation_speed") {
            root.speedMultiplier = value
            root.applyPreview()
        } else {
            root.setOverride(row, value)
        }
    }

    function toggleRow(row) {
        root.setOverride(row, !(root.valueFor(row) === true))
    }

    function cycle(row, direction) {
        var options = row.list ? (root.pipelineOptions[row.id] || []) : row.options
        if (!options || options.length === 0) return
        var currentValue = String(root.valueFor(row))
        var index = options.indexOf(currentValue)
        if (index < 0) index = 0
        var next = options[(index + direction + options.length) % options.length]
        if (row.type === "pipeline") root.setPipeline(row, next)
        else root.setOverride(row, next)
    }

    function moveRow(delta) {
        var count = root.activeRows.length
        if (count === 0) return
        root.rowIndex = (root.rowIndex + delta + count) % count
    }

    function moveSection(delta) {
        var count = root.sections.length
        root.sectionIndex = (root.sectionIndex + delta + count) % count
        root.rowIndex = 0
    }

    // ----------------------------------------------------------------- window

    PanelWindow {
        id: window
        visible: root.opened
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: Style.px(760)
        implicitHeight: Style.px(470)

        WlrLayershell.namespace: "hypr-shell-looknfeel"
        WlrLayershell.layer: WlrLayer.Overlay
        // Primed Exclusive then dropped to OnDemand, matching the bars: it is
        // what lets a click outside reach the target window on the first click.
        WlrLayershell.keyboardFocus: !root.opened ? WlrKeyboardFocus.None
            : root.exclusivePhase ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        Rectangle {
            anchors.fill: parent
            radius: root.shell.rounding
            // Same card as PopupCard, with a focus-aware active/neutral edge.
            color: root.shell.alpha(root.shell.role("bg", root.shell.background), .94)
            border.width: "general:border_size" in root.themeDefaults
                ? Number(root.themeDefaults["general:border_size"]) : 2
            border.color: root.shell.alpha(
                root.shell.role(keyCatcher.activeFocus ? "act_br" : "br", root.shell.foreground),
                keyCatcher.activeFocus ? .45 : .25
            )
            Behavior on border.color {
                ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic }
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    var row = root.activeRows[root.rowIndex]
                    switch (event.key) {
                    case Qt.Key_Escape: root.close(); break
                    case Qt.Key_Up: case Qt.Key_K: root.moveRow(-1); break
                    case Qt.Key_Down: case Qt.Key_J: root.moveRow(1); break
                    case Qt.Key_Left: case Qt.Key_H: if (row) root.adjust(row, -1); break
                    case Qt.Key_Right: case Qt.Key_L: if (row) root.adjust(row, 1); break
                    case Qt.Key_Tab: root.moveSection(1); break
                    case Qt.Key_Backtab: root.moveSection(-1); break
                    case Qt.Key_Backspace: if (row) root.resetRow(row); break
                    default: return
                    }
                    event.accepted = true
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.popupPadding
                    spacing: Style.rowGap

                    PopupHero {
                        Layout.fillWidth: true
                        shell: root.shell
                        title: "Look & Feel"
                        status: root.themeKey
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Style.sectionGap

                        ListView {
                            id: sectionList
                            Layout.preferredWidth: Style.px(150)
                            Layout.fillHeight: true
                            model: root.sections
                            clip: true
                            currentIndex: root.sectionIndex
                            spacing: Style.xxs
                            delegate: Rectangle {
                                id: sectionRow
                                required property int index
                                required property var modelData
                                width: sectionList.width
                                height: Style.popupRowHeight
                                radius: root.shell.rounding
                                color: sectionRow.index === root.sectionIndex
                                    ? root.shell.hoverFill(2)
                                    : sectionArea.containsMouse ? root.shell.hoverFill(1) : "transparent"
                                Behavior on color { ColorAnimation { duration: Style.hoverDuration } }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.controlPaddingX
                                    text: sectionRow.modelData.title
                                    color: sectionRow.index === root.sectionIndex
                                        ? root.shell.foreground : root.shell.alpha(root.shell.foreground, .6)
                                    font.family: root.shell.fontFamily
                                    font.pixelSize: Style.body
                                }
                                MouseArea {
                                    id: sectionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.sectionIndex = sectionRow.index; root.rowIndex = 0 }
                                }
                            }
                        }

                        ListView {
                            id: rowList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: root.activeRows
                            clip: true
                            spacing: Style.xxs
                            currentIndex: root.rowIndex
                            delegate: LooknfeelRow {
                                id: optionRow
                                required property int index
                                required property var modelData
                                width: rowList.width
                                shell: root.shell
                                row: optionRow.modelData
                                value: root.valueFor(optionRow.modelData)
                                options: optionRow.modelData.list
                                    ? (root.pipelineOptions[optionRow.modelData.id] || [])
                                    : (optionRow.modelData.options || [])
                                overridden: root.isOverridden(optionRow.modelData)
                                selected: optionRow.index === root.rowIndex
                                onChanged: value => {
                                    root.rowIndex = optionRow.index
                                    if (optionRow.modelData.id === "animation_speed") {
                                        root.speedMultiplier = value
                                        root.applyPreview()
                                    } else {
                                        root.setOverride(optionRow.modelData, value)
                                    }
                                }
                                onToggled: {
                                    root.rowIndex = optionRow.index
                                    root.toggleRow(optionRow.modelData)
                                }
                                onCycled: direction => {
                                    root.rowIndex = optionRow.index
                                    root.cycle(optionRow.modelData, direction)
                                }
                                onChosen: value => {
                                    root.rowIndex = optionRow.index
                                    if (optionRow.modelData.type === "pipeline")
                                        root.setPipeline(optionRow.modelData, value)
                                    else root.setOverride(optionRow.modelData, value)
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.errorText !== ""
                        text: root.errorText
                        color: root.shell.role("error", root.shell.accent)
                        font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.errorText === ""
                        text: "↑↓ row   ←→ adjust   Tab section   Backspace reset   Esc close"
                        color: root.shell.alpha(root.shell.foreground, .45)
                        font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "looknfeel"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
        function isOpen(): bool { return root.opened }
    }
}

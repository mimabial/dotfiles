import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons as Commons
import "js/Schema.js" as Schema
import "js/Model.js" as Model
import "core"

Item {
    id: root

    visible: false

    required property var shell
    readonly property string displayName: "Alt+Tab"

    SettingsStore { id: settingsStore }
    property alias store: settingsStore
    readonly property var defaults: Schema.defaults()
    readonly property var cfg: Schema.resolve(settingsStore.values)

    function setValue(key, value) { settingsStore.set(key, Schema.clean(key, value)) }
    UiState {
        id: ux
        shell: root.shell
        barFg: Commons.Color.bar.text
        barBg: Commons.Color.bar.background
        themeAccent: Commons.Color.accent
        fontName: Commons.Style.font.family
    }
    property alias ui: ux

    property var info: ({ windows: [], focusedMonitor: "", activeWorkspace: 1 })
    property bool ready: false
    readonly property int windowCount: info.windows.length

    function refresh() {
        if (snapshot.running) { refreshAgain = true; return }
        snapshot.running = true
    }
    property bool refreshAgain: false

    Process {
        id: snapshot
        command: ["hyprctl", "-j", "--batch", "clients ; monitors"]
        stdout: StdioCollector {
            onStreamFinished: root.absorbSnapshot(text)
        }
        onExited: {
            if (root.refreshAgain) { root.refreshAgain = false; Qt.callLater(root.refresh) }
        }
    }

    function absorbSnapshot(text) {
        var snap
        try { const parts = String(text).trim().split(/\n\s*\n/).map(part => JSON.parse(part)); snap = {clients: parts[0], monitors: parts[1]} } catch (e) { return }
        info = Model.parseSnapshot(snap)
        ready = true
        drainCommands()
    }

    readonly property var refreshEvents: ["openwindow", "closewindow", "movewindowv2", "activewindowv2",
        "workspacev2", "focusedmonv2", "moveworkspacev2", "monitoraddedv2", "monitorremovedv2"]

    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) {
            var name = ""
            var data = ""
            try { name = String(event.name); data = String(event.data) } catch (e) { return }
            if (name === "custom" && data.indexOf("altscape:") === 0) {
                var action = data.slice("altscape:".length)
                if (action === "settings") root.togglePanel(true)
                else if (action === "next") root.switchWindow(1)
                else if (action === "prev") root.switchWindow(-1)
                else if (action === "release") root.switchWindow(0)
                return
            }
            if (root.refreshEvents.indexOf(name) >= 0) root.refresh()
        }
    }

    function validAddress(a) { return /^0x[0-9a-fA-F]+$/.test(String(a)) }

    function focusWindow(address) {
        if (!validAddress(address)) return false
        const window = 'window = "address:' + address + '"'
        Hyprland.dispatch('(function() hl.dispatch(hl.dsp.focus({ ' + window + ' })); return hl.dsp.window.alter_zorder({ ' + window + ', mode = "top" }) end)()')
        return true
    }

    property var pendingCommands: []
    property var cycleWindows: []
    property string cycleAddress: ""

    function resetCycle() { cycleWindows = []; cycleAddress = "" }
    onCfgChanged: resetCycle()

    function switchWindow(step) {
        if (!ready || !settingsStore.loaded) {
            pendingCommands = pendingCommands.concat(step)
            return true
        }
        if (step === 0) { resetCycle(); return true }
        shell.closePopup()
        const cycle = Model.cycle(info, cfg, cycleWindows, cycleAddress, step)
        cycleWindows = cycle.windows
        cycleAddress = cycle.address
        return cycleAddress !== "" && focusWindow(cycleAddress)
    }
    function drainCommands() {
        if (!ready || !settingsStore.loaded) return
        const commands = pendingCommands
        pendingCommands = []
        for (const command of commands) switchWindow(command)
    }
    function closePanel() {
        if (shell.popupName === "altscape") shell.closePopup()
    }
    function togglePanel(centered) {
        shell.togglePopup("altscape", centered === true)
    }
    Connections {
        target: settingsStore
        function onLoadedChanged() { root.drainCommands() }
    }
    Component.onCompleted: refresh()
    IpcHandler {
        target: "altscape"
        function open(): void { root.togglePanel(true) }
        function next(): void { root.switchWindow(1) }
        function prev(): void { root.switchWindow(-1) }
        function release(): void { root.switchWindow(0) }
        function close(): void { root.resetCycle(); root.closePanel() }
        function status(): string {
            return JSON.stringify({windows: root.windowCount, scope: root.cfg.scope,
                ready: root.ready && settingsStore.loaded, opened: root.shell.popupName === "altscape",
                selected: root.cycleAddress})
        }
    }
}

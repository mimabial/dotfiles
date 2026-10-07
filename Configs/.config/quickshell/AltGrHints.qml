pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons as Commons

Scope {
    id: root
    required property var shell
    readonly property string owner: String(Date.now())
    readonly property string luaPath: decodeURIComponent(Qt.resolvedUrl("altgr-hints.lua").toString().replace(/^file:\/\//, ""))
    property var rows: []
    property int level: 0

    function refresh() {
        root.level = 0
        keymap.running = true
    }

    Process {
        id: keymap
        command: ["python3", root.shell.home + "/.local/lib/hypr/quickshell/altgr-hints.py"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.rows = data.rows
                    const codes = Object.entries(data.codes).map(entry => entry[0] + " = " + entry[1]).join(", ")
                    listener.command = ["hyprctl", "eval", "dofile(" + JSON.stringify(root.luaPath) + ")({" + codes
                        + "}, " + JSON.stringify(root.owner) + ", " + String(data.capsLock) + ")"]
                    listener.running = true
                } catch (error) { console.warn("AltGr hints: " + error) }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("AltGr hints: " + text.trim()) }
    }
    Process {
        id: listener
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "ok") console.warn("AltGr hints: " + text.trim()) }
    }
    Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval",
        "local hints = rawget(_G, '__altgr_hints'); if hints and hints.owner == " + JSON.stringify(root.owner)
        + " then hints.subscription:remove(); _G.__altgr_hints = nil end"])

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("altgr-hints>>")) root.level = Number(event.data.slice("altgr-hints>>".length))
            else if (event.name === "configreloaded" || event.name === "activelayout") root.refresh()
        }
    }

    LayerBlur { surface: "hypr-shell-altgr"; enabled: root.shell.prefs.barBlur; ignoreAlpha: 0.1 }
    TextMetrics { id: cellMetrics; font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.body; text: "◌◌" }

    PanelWindow {
        id: window
        visible: root.level > 0 && root.rows.length > 0
        screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        implicitWidth: content.implicitWidth + Commons.Style.spacing.panelPadding * 2
        implicitHeight: content.implicitHeight + Commons.Style.spacing.panelPadding * 2
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.namespace: "hypr-shell-altgr"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        PopupSurface {
            shell: root.shell
            anchors.fill: parent

            Column {
                id: content
                anchors.centerIn: parent
                spacing: Commons.Style.spacing.controlGap

                Repeater {
                    model: root.rows
                    delegate: Row {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Commons.Style.spacing.sm

                        Repeater {
                            model: parent.modelData
                            delegate: PopupRow {
                                id: cell
                                shell: root.shell
                                required property var modelData
                                readonly property string symbol: modelData.symbols[Math.max(0, root.level - 1)]
                                width: cellMetrics.width + Commons.Style.spacing.controlPaddingX * 2
                                title: cell.symbol
                                detail: cell.modelData.key
                                titleColor: cell.symbol.startsWith("◌") ? root.shell.accent : root.shell.foreground
                                centerTitle: true
                                detailAlignment: Text.AlignHCenter
                                interactive: false
                                color: root.shell.hoverFill()
                            }
                        }
                    }
                }
                PopupHint {
                    shell: root.shell
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "AltGr" + (root.level % 2 === 0 ? " + Shift" : "") + (root.level > 2 ? " · Caps Lock" : "") + " · ◌ dead key"
                }
            }
        }
    }
}

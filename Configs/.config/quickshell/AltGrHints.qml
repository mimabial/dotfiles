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
    readonly property bool capsLock: root.level > 2
    readonly property bool shiftHeld: root.level % 2 === 0
    readonly property int unshifted: root.capsLock ? 2 : 0
    readonly property int shifted: root.unshifted + 1
    readonly property color unshiftedColor: root.shiftHeld ? root.shell.mutedText : root.shell.foreground
    readonly property color shiftedColor: root.shell.accent
    readonly property int glyphSize: Commons.Style.font.body * 2
    readonly property int keyGap: Commons.Style.spacing.sm
    readonly property int keyInset: Commons.Style.spacing.md
    readonly property real faceSize: glyphMetrics.height + captionMetrics.height * 2
    readonly property real keyUnit: root.faceSize + root.keyGap

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
    FontMetrics { id: glyphMetrics; font.family: root.shell.fontFamily; font.pixelSize: root.glyphSize }
    FontMetrics { id: captionMetrics; font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption }

    component KeyLegend: Item {
        id: legend
        property string symbol
        property bool dead
        property color color
        property int pixelSize
        implicitWidth: Math.max(glyph.implicitWidth, legend.dead ? dottedCircle.implicitWidth : 0)
        implicitHeight: glyph.implicitHeight
        Text { id: dottedCircle; anchors.centerIn: parent; visible: legend.dead; text: "◌"; color: root.shell.faintText; font: glyph.font }
        Text { id: glyph; anchors.centerIn: parent; text: legend.symbol; color: legend.color; font.family: root.shell.fontFamily; font.pixelSize: legend.pixelSize }
    }

    component DeadKeyName: Text {
        width: parent.width
        height: captionMetrics.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 1
        font.family: root.shell.fontFamily
        font.pixelSize: Commons.Style.font.caption
    }

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
            id: card
            shell: root.shell
            anchors.fill: parent

            Column {
                id: content
                anchors.centerIn: parent
                spacing: Commons.Style.spacing.controlGap

                Row {
                    Text { id: altgrHeader; text: "altgr"; color: root.unshiftedColor; font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.body }
                    Text { text: " · "; color: root.shell.mutedText; font: altgrHeader.font }
                    Text { text: "shift"; color: root.shiftedColor; font: altgrHeader.font }
                    Text { text: (root.capsLock ? " · caps lock" : "") + " · ◌ dead key"; color: root.shell.mutedText; font: altgrHeader.font }
                }

                Column {
                    spacing: root.keyGap

                    Repeater {
                        model: root.rows
                        delegate: Row {
                            id: keyRow
                            required property var modelData
                            leftPadding: keyRow.modelData.indent * root.keyUnit
                            spacing: root.keyGap

                            Repeater {
                                model: keyRow.modelData.keys
                                delegate: Rectangle {
                                    id: key
                                    required property var modelData
                                    readonly property bool letter: key.modelData.key.toLowerCase() !== key.modelData.key
                                    width: key.modelData.width * root.keyUnit - root.keyGap
                                    height: deadKeyNames.height + root.faceSize
                                    radius: root.shell.rounding
                                    color: root.shell.hoverFill(key.letter ? 2 : 1)
                                    border.color: card.border.color
                                    border.width: card.border.width

                                    Column {
                                        id: deadKeyNames
                                        width: parent.width
                                        topPadding: Commons.Style.spacing.xxs
                                        DeadKeyName { text: key.modelData.dead[root.unshifted]; color: root.unshiftedColor }
                                        DeadKeyName { text: key.modelData.dead[root.shifted]; color: root.shiftedColor }
                                    }

                                    Item {
                                        y: deadKeyNames.height
                                        width: parent.width
                                        height: root.faceSize

                                        KeyLegend {
                                            anchors.centerIn: parent
                                            symbol: key.modelData.symbols[root.unshifted]
                                            dead: key.modelData.dead[root.unshifted] !== ""
                                            color: root.unshiftedColor
                                            pixelSize: root.glyphSize
                                        }
                                        KeyLegend {
                                            anchors { top: parent.top; right: parent.right; margins: root.keyInset }
                                            symbol: key.modelData.symbols[root.shifted]
                                            dead: key.modelData.dead[root.shifted] !== ""
                                            color: root.shiftedColor
                                            pixelSize: Commons.Style.font.caption
                                        }
                                        Text {
                                            anchors { bottom: parent.bottom; left: parent.left; margins: root.keyInset }
                                            text: key.modelData.key
                                            color: root.shell.mutedText
                                            font.family: root.shell.fontFamily
                                            font.pixelSize: Commons.Style.font.caption
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

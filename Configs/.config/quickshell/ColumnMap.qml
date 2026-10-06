pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

Item {
    id: root
    required property var shell
    required property color inactiveColor
    required property color inactiveWindowColor
    readonly property var workspace: Hyprland.focusedWorkspace
    readonly property var monitor: workspace?.monitor ?? null
    readonly property rect viewport: monitor ? Qt.rect(monitor.x, monitor.y, monitor.width / monitor.scale, monitor.height / monitor.scale) : Qt.rect(0, 0, 0, 0)
    readonly property var windows: workspace?.toplevels.values.filter(window => window.lastIpcObject.at) ?? []
    readonly property bool leftHidden: windows.some(window => window.lastIpcObject.at[0] < viewport.x)
    readonly property bool rightHidden: windows.some(window => window.lastIpcObject.at[0] + window.lastIpcObject.size[0] > viewport.x + viewport.width)
    readonly property real hairline: Style.px(1)
    readonly property real stroke: Style.px(1)
    readonly property real padding: Style.px(2)
    readonly property real windowGap: Style.px(2)
    readonly property real frameMargin: Style.px(3)
    readonly property real frameHeight: Style.controlHeight - frameMargin * 2
    readonly property real mapScale: viewport.height > 0 ? (frameHeight - padding * 2) / viewport.height : 0
    readonly property var geometryEvents: ["activewindowv2", "movewindowv2", "changefloatingmode", "fullscreen", "custom"]
    implicitWidth: monitor ? strip.implicitWidth : 0
    implicitHeight: monitor ? Style.controlHeight : 0

    component HiddenMarker: Item {
        id: marker
        required property bool hidden
        width: root.stroke * 2
        height: root.frameHeight
        Rectangle {
            anchors.centerIn: parent
            width: root.stroke
            height: parent.height / 2
            color: marker.hidden ? root.shell.accent : root.inactiveColor
        }
    }

    component WindowMark: Rectangle {
        required property var modelData
        readonly property var ipc: modelData.lastIpcObject
        x: (ipc.at[0] - root.viewport.x) * root.mapScale + root.windowGap / 2
        y: (ipc.at[1] - root.viewport.y) * root.mapScale + root.windowGap / 2
        width: ipc.size[0] * root.mapScale - root.windowGap
        height: ipc.size[1] * root.mapScale - root.windowGap
        color: modelData === Hyprland.activeToplevel ? root.shell.alpha(root.shell.accent, 1) : root.inactiveWindowColor
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (root.geometryEvents.includes(event.name)) Hyprland.refreshToplevels() }
    }

    Row {
        id: strip
        y: root.frameMargin
        spacing: root.hairline * 2

        HiddenMarker { hidden: root.leftHidden }

        Rectangle {
            id: frame
            width: screenMap.width + root.padding * 2
            height: root.frameHeight
            color: "transparent"
            border.width: root.stroke
            border.color: root.inactiveColor

            Item {
                id: screenMap
                anchors.centerIn: parent
                width: root.viewport.width * root.mapScale
                height: root.viewport.height * root.mapScale
                clip: true

                Repeater {
                    model: root.windows
                    delegate: WindowMark {}
                }
            }

            MouseArea {
                id: pointer
                readonly property var hoveredWindow: containsMouse ? (screenMap.childAt(mouseX, mouseY) as WindowMark)?.modelData ?? null : null
                anchors.fill: screenMap
                hoverEnabled: true
                onClicked: if (hoveredWindow) Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.focus({window="address:0x' + hoveredWindow.address + '"})'
                    : "focuswindow address:0x" + hoveredWindow.address)
            }

            BarTooltip { anchorItem: frame; shell: root.shell; text: pointer.hoveredWindow?.title ?? ""; hovered: pointer.hoveredWindow !== null }
        }

        HiddenMarker { hidden: root.rightHidden }
    }
}

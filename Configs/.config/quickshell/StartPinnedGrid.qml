import QtQuick
import Quickshell
import Quickshell.Widgets

Column {
    id: root
    required property var shell
    property var apps: []
    signal launched(var app)
    signal unpinned(var app)
    visible: apps.length > 0
    spacing: Style.sm

    PopupSection { shell: root.shell; text: "PINNED" }
    Grid {
        columns: 4
        columnSpacing: Style.lg
        rowSpacing: Style.lg
        width: parent.width
        Repeater {
            model: root.apps
            Rectangle {
                required property var modelData
                readonly property bool hovered: tileMouse.containsMouse
                width: Math.floor((root.width - Style.lg * 3) / 4)
                height: 62
                radius: root.shell.rounding
                color: hovered ? root.shell.alpha(root.shell.foreground, .1) : "transparent"
                border.color: hovered ? root.shell.alpha(root.shell.role("br", root.shell.foreground), .35) : "transparent"
                Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.sm * 2
                    spacing: Style.xs
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 28; implicitHeight: 28
                        source: Quickshell.iconPath(modelData.icon, true)
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.name
                        elide: Text.ElideRight
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption
                    }
                }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => event.button === Qt.RightButton
                        ? root.unpinned(modelData) : root.launched(modelData)
                }
            }
        }
    }
}

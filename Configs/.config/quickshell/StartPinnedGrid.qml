pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets

Column {
    id: root
    required property var shell
    property var apps: []
    property int cursorIndex: -1
    readonly property int columns: 4
    readonly property int tileHeight: Style.px(62)
    readonly property int iconSize: Style.px(28)
    signal launched(var app)
    signal unpinned(var app)
    signal pointed(int index, point position)
    visible: apps.length > 0
    spacing: Style.sm

    PopupSection { shell: root.shell; text: "PINNED" }
    Grid {
        columns: root.columns
        columnSpacing: Style.lg
        rowSpacing: Style.lg
        width: parent.width
        Repeater {
            model: root.apps
            Rectangle {
                id: pinnedApp
                required property var modelData
                required property int index
                width: Math.floor((root.width - Style.lg * (root.columns - 1)) / root.columns)
                height: root.tileHeight
                radius: root.shell.rounding
                color: pinnedApp.index === root.cursorIndex ? root.shell.hoverFill() : "transparent"
                Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.sm * 2
                    spacing: Style.xs
                    IconImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: root.iconSize; implicitHeight: root.iconSize
                        source: Quickshell.iconPath(pinnedApp.modelData.icon, true)
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: pinnedApp.modelData.name
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
                    onPositionChanged: mouse => root.pointed(pinnedApp.index, tileMouse.mapToGlobal(mouse.x, mouse.y))
                    onClicked: event => event.button === Qt.RightButton
                        ? root.unpinned(pinnedApp.modelData) : root.launched(pinnedApp.modelData)
                }
            }
        }
    }
}

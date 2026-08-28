import QtQuick
import "../Commons" as Commons

BorderSurface {
    id: root

    property string text: ""
    property bool selected: false
    property bool focusable: false
    property bool bordered: false
    property color foreground: Commons.Color.foreground
    property color accent: Commons.Color.accent
    signal clicked()

    activeFocusOnTab: focusable
    radius: Commons.Style.cornerRadius
    color: selected || mouse.containsMouse || activeFocus
        ? Commons.Util.alpha(accent, selected ? 0.24 : 0.14)
        : "transparent"
    borderSpec: bordered
        ? Commons.Border.flat(selected || activeFocus ? accent : Commons.Util.alpha(foreground, 0.38), Commons.Style.normalBorderWidth)
        : Commons.Border.none()

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? root.accent : root.foreground
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.focusable) root.forceActiveFocus()
            root.clicked()
        }
    }
}

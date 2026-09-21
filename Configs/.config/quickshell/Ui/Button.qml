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
    property string fontFamily: Commons.Style.font.menuFamily
    property real fontSize: Commons.Style.font.caption
    property real horizontalPadding: Commons.Style.space(10)
    property real verticalPadding: Commons.Style.space(6)
    signal clicked()

    activeFocusOnTab: focusable
    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2
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
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
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

import QtQuick
import Quickshell.Widgets

Rectangle {
    id: root
    required property var shell
    property string icon: ""
    property string iconSource: ""
    property string title: ""
    property string detail: ""
    property string value: ""
    property bool active: false
    // marks the row for PopupCard's keyboard cursor, and shows where it sits
    readonly property bool navigable: true
    readonly property bool hovered: mouse.containsMouse
    property bool cursored: false
    // for rows that are a bare label, with no icon or value to align against
    property bool centerTitle: false
    signal clicked(int button)
    implicitHeight: Math.max(Style.popupRowHeight, textColumn.implicitHeight + Style.controlPaddingY * 2)
    readonly property color highlight: active ? shell.alpha(shell.role("act_br", shell.accent), .5)
        : cursored ? shell.alpha(shell.role("hvr_br", shell.foreground), .45)
        : mouse.containsMouse ? shell.alpha(shell.role("br", shell.foreground), .35)
        : "transparent"
    color: (mouse.containsMouse || cursored) ? shell.alpha(shell.foreground, .1)
        : active ? shell.alpha(shell.role("act_bg", shell.accent), .2) : "transparent"
    border.color: highlight
    radius: shell.rounding
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

    Row {
        anchors.fill: parent; anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        spacing: Style.controlPaddingX
        // centred in its fixed column so the gap to the border matches the gap to the text
        IconImage { id: iconImage; visible: root.iconSource !== ""; implicitWidth: 18; implicitHeight: 18; anchors.verticalCenter: parent.verticalCenter; source: root.iconSource }
        Text { id: iconText; visible: root.icon !== ""; width: 22; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: root.icon; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title + 3 }
        Column {
            id: textColumn
            width: parent.width - (iconText.visible ? iconText.width + parent.spacing : 0) - (iconImage.visible ? iconImage.width + parent.spacing : 0) - (valueText.visible ? valueText.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text { width: parent.width; text: root.title; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle; font.bold: root.active; elide: Text.ElideRight; horizontalAlignment: root.centerTitle ? Text.AlignHCenter : Text.AlignLeft }
            Text { visible: text !== ""; width: parent.width; text: root.detail; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
        }
        Text { id: valueText; visible: text !== ""; anchors.verticalCenter: parent.verticalCenter; text: root.value; color: root.shell.alpha(root.shell.foreground, .7); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }
    MouseArea { id: mouse; anchors.fill: parent; enabled: root.enabled; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton; onClicked: event => root.clicked(event.button) }
}

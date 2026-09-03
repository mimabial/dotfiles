import QtQuick

// A popup's own name and live status line. Kept distinct from PopupSection so a
// panel's title never reads as one of its section headers.
Item {
    id: root
    required property var shell
    property string icon: ""
    property string title: ""
    property string status: ""
    property color statusColor: shell.alpha(shell.foreground, .6)
    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(heroIcon.visible ? heroIcon.implicitHeight : 0, labels.implicitHeight)

    Text {
        id: heroIcon
        visible: root.icon !== ""; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        text: root.icon; color: root.shell.foreground
        font.family: root.shell.fontFamily; font.pixelSize: Style.displayLarge
    }
    Column {
        id: labels
        anchors.left: heroIcon.visible ? heroIcon.right : parent.left
        anchors.leftMargin: heroIcon.visible ? Style.xxxl : 0
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.xxs
        Text {
            width: parent.width; text: root.title; elide: Text.ElideRight
            color: root.shell.foreground; font.family: root.shell.fontFamily
            font.pixelSize: Style.title; font.bold: true
        }
        Text {
            visible: text !== ""
            width: parent.width; text: root.status.toUpperCase(); elide: Text.ElideRight
            color: root.statusColor; font.family: root.shell.fontFamily
            font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1.2
        }
    }
}

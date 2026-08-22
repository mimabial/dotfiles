import QtQuick

// A popup's own name and live status line. Kept distinct from PopupSection so a
// panel's title never reads as one of its section headers.
Column {
    id: root
    required property var shell
    property string title: ""
    property string status: ""
    width: parent ? parent.width : implicitWidth
    spacing: Style.xxs

    Text {
        width: parent.width; text: root.title; elide: Text.ElideRight
        color: root.shell.foreground; font.family: root.shell.fontFamily
        font.pixelSize: Style.title; font.bold: true
    }
    Text {
        visible: text !== ""
        width: parent.width; text: root.status.toUpperCase(); elide: Text.ElideRight
        color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily
        font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1.2
    }
}

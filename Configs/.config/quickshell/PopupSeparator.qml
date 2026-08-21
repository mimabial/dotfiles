import QtQuick

Rectangle {
    id: root
    required property var shell
    property real strength: 0.12
    width: parent ? parent.width : implicitWidth
    implicitWidth: 100
    implicitHeight: 1
    height: 1
    color: root.shell.alpha(root.shell.foreground, root.strength)
}

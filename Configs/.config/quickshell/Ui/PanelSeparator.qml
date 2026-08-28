import QtQuick
import "../Commons" as Commons

Rectangle {
    property color foreground: Commons.Color.foreground
    property real strength: 0.12

    width: parent ? parent.width : implicitWidth
    implicitWidth: 100
    implicitHeight: 1
    height: 1
    color: Commons.Util.alpha(foreground, strength)
}

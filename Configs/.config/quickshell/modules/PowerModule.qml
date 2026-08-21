import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

Item {
    id: root
    required property var shell
    property bool popupsAllowed: true
    readonly property var box: root.shell.style.box("power")
    function boxColor(key) {
        const spec = root.box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? root.shell.alpha(root.shell.role(spec[0], root.shell.foreground), spec[1])
            : root.shell.role(spec, root.shell.foreground)
    }
    Layout.fillWidth: true; implicitWidth: powerStatus.implicitWidth; implicitHeight: powerStatus.implicitHeight
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0]; anchors.rightMargin: parent.box.margin[1]
        anchors.bottomMargin: parent.box.margin[2]; anchors.leftMargin: parent.box.margin[3]
        radius: root.shell.moduleRadius; color: root.boxColor("fill")
        border.color: root.boxColor("outline"); border.width: powerEdge.replacesOutline ? 0 : Math.max(1, parent.box.border)
    }
    Status {
        id: powerStatus; shell: root.shell; reverse: true; showAudio: false; showNetwork: false; popupsEnabled: root.popupsAllowed
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0] + parent.box.padding[0]; anchors.rightMargin: parent.box.margin[1] + parent.box.padding[1]
        anchors.bottomMargin: parent.box.margin[2] + parent.box.padding[2]; anchors.leftMargin: parent.box.margin[3] + parent.box.padding[3]
    }
    ModuleEdge { id: powerEdge; shell: root.shell }
}

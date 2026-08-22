import QtQuick
import QtQuick.Layouts
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
    // the group's own frame has to grow the item, not eat into the children
    readonly property real borderWidth: powerEdge.replacesOutline ? 0 : Math.max(1, box.border)
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * borderWidth
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderWidth
    Layout.fillWidth: true; implicitWidth: powerStatus.implicitWidth + spanX; implicitHeight: powerStatus.implicitHeight + spanY
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0]; anchors.rightMargin: parent.box.margin[1]
        anchors.bottomMargin: parent.box.margin[2]; anchors.leftMargin: parent.box.margin[3]
        radius: root.shell.moduleRadius; color: root.boxColor("fill")
        border.color: root.boxColor("outline"); border.width: root.borderWidth
    }
    Status {
        id: powerStatus; shell: root.shell; reverse: true; showAudio: false; showNetwork: false; popupsEnabled: root.popupsAllowed
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0] + root.borderWidth + parent.box.padding[0]; anchors.rightMargin: parent.box.margin[1] + root.borderWidth + parent.box.padding[1]
        anchors.bottomMargin: parent.box.margin[2] + root.borderWidth + parent.box.padding[2]; anchors.leftMargin: parent.box.margin[3] + root.borderWidth + parent.box.padding[3]
    }
    ModuleEdge { id: powerEdge; shell: root.shell }
}

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property string name
    required property color color
    required property int size
    property string context: "status"
    // icon themes disagree on where the context folder sits, so a style names
    // the whole path with {context} standing in for it
    property string directory: ""
    property string svg: ""
    readonly property bool loaded: svg !== ""
    implicitWidth: size; implicitHeight: size
    FileView {
        path: Quickshell.env("HOME") + "/.local/share/icons/" + (root.directory || "MacTahoe-dark/{context}/symbolic").replace("{context}", root.context)
            + "/" + root.name + "-symbolic.svg"
        printErrors: false
        onLoaded: root.svg = text()
        onLoadFailed: root.svg = ""
    }
    Image {
        anchors.fill: parent; opacity: root.color.a
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        source: root.svg ? "data:image/svg+xml;utf8," + encodeURIComponent(root.svg.replace(/#[0-9a-fA-F]{6}\b/g, String(Qt.rgba(root.color.r, root.color.g, root.color.b, 1)))) : ""
    }
}

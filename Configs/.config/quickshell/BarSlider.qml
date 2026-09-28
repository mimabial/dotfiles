import QtQuick

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    readonly property var trough: shell.style.box(css + " trough")
    property real value: 0
    property real from: 0
    property real to: 1
    signal moved(real value)
    implicitWidth: trough.minWidth + box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.borderWidth
    implicitHeight: trough.minHeight + box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.borderWidth
    property real step: (to - from) / 20
    function set(target) { moved(Math.max(from, Math.min(to, target))) }
    function move(x) { set(from + (x - track.x) / track.width * (to - from)) }
    Rectangle {
        id: track; anchors.centerIn: parent; width: root.trough.minWidth; height: root.trough.minHeight; radius: height / 2
        color: root.shell.alpha(root.shell.background, .2); border.color: root.shell.styleColor(root.trough.borderColor, Qt.rgba(0, 0, 0, 0.45))
        border.width: root.trough.borderWidth
        Rectangle { x: track.border.width; y: track.border.width; width: (track.width - 2 * x) * Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from))); height: track.height - 2 * y; radius: height / 2; color: root.shell.alpha(root.shell.role("c11", root.shell.accent), 0.2) }
    }
    MouseArea {
        anchors.fill: parent; preventStealing: true
        onPressed: event => root.move(event.x)
        onPositionChanged: event => { if (pressed) root.move(event.x) }
        onWheel: event => { if (event.angleDelta.y) root.set(root.value + event.angleDelta.y / 120 * root.step) }
    }
}

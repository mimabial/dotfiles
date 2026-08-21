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
    implicitWidth: trough.minWidth + box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
    implicitHeight: trough.minHeight + box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
    function move(x) { moved(from + Math.max(0, Math.min(1, (x - track.x) / track.width)) * (to - from)) }
    Rectangle {
        id: track; anchors.centerIn: parent; width: root.trough.minWidth; height: root.trough.minHeight
        color: root.shell.alpha(root.shell.background, .2); border.color: root.shell.alpha(root.shell.role("c8", root.shell.foreground), .2)
        border.width: Math.max(1, root.trough.border)
        Rectangle { width: parent.width * Math.max(0, Math.min(1, (root.value - root.from) / (root.to - root.from))); height: parent.height; color: root.shell.alpha(root.shell.role("c11", root.shell.accent), .3) }
    }
    MouseArea { anchors.fill: parent; onPressed: event => root.move(event.x); onPositionChanged: event => { if (pressed) root.move(event.x) } }
    ModuleEdge { shell: root.shell }
}

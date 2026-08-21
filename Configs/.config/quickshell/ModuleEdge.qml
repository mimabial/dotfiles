import QtQuick

// Single-side rules, which Rectangle cannot draw (it is all four sides or none).
// Clip native rounded borders so edges match normal borders exactly.
Item {
    id: root
    required property var shell
    readonly property var box: parent && parent.box ? parent.box : null
    readonly property var spec: box && box.edge ? box.edge : null
    readonly property bool replacesOutline: spec !== null && !box.outline
    readonly property bool edgeTop: spec ? spec.top === true : false
    readonly property bool edgeRight: spec ? spec.right === true : false
    readonly property bool edgeBottom: spec ? spec.bottom === true : false
    readonly property bool edgeLeft: spec ? spec.left === true : false
    property bool hovered: false
    property bool active: false
    readonly property color line: {
        const paint = hovered && box.hover && "border" in box.hover ? box.hover.border
            : spec && spec.color ? spec.color : active ? ["act_br", 1] : ["br", .3]
        if (!paint) return "transparent"
        return shell.alpha(shell.role(paint[0], shell.foreground), paint[1])
    }
    readonly property real thickness: box && box.border > 0 ? box.border : 1
    readonly property real radius: spec && spec.radius !== undefined ? spec.radius : parent.radius !== undefined ? parent.radius : shell.moduleRadius
    readonly property var segments: {
        const c = Math.min(Math.max(radius, thickness), width / 2, height / 2)
        const t = edgeTop ? c : 0, b = edgeBottom ? c : 0
        return [
            edgeTop && {x: 0, y: 0, w: width, h: c},
            edgeRight && {x: width-c, y: t, w: c, h: height-t-b},
            edgeBottom && {x: 0, y: height-c, w: width, h: c},
            edgeLeft && {x: 0, y: t, w: c, h: height-t-b}
        ].filter(Boolean)
    }

    visible: spec !== null
    anchors.fill: parent
    anchors.topMargin: box ? box.margin[0] : 0
    anchors.rightMargin: box ? box.margin[1] : 0
    anchors.bottomMargin: box ? box.margin[2] : 0
    anchors.leftMargin: box ? box.margin[3] : 0

    Repeater {
        model: root.segments
        delegate: Item {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            clip: true
            Rectangle {
                x: -parent.x; y: -parent.y; width: root.width; height: root.height
                radius: root.radius; color: "transparent"
                border.color: root.line; border.width: root.thickness
            }
        }
    }
}

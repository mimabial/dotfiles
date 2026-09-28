pragma ComponentBehavior: Bound
import QtQuick

// Rectangle paints every border side; clipping it keeps selected sides rounded.
Item {
    id: root
    required property var shell
    required property var host
    readonly property var box: host && host.box ? host.box : null
    readonly property real topWidth: box?.borderTopWidth || 0
    readonly property real rightWidth: box?.borderRightWidth || 0
    readonly property real bottomWidth: box?.borderBottomWidth || 0
    readonly property real leftWidth: box?.borderLeftWidth || 0
    readonly property bool hasSides: topWidth > 0 || rightWidth > 0 || bottomWidth > 0 || leftWidth > 0
    readonly property bool replacesBorder: hasSides && !box.borderColor
    property bool hovered: false
    readonly property real radius: box?.borderRadius !== undefined ? box.borderRadius : host.radius !== undefined ? host.radius : shell.moduleRadius
    function sideColor(side) {
        const key = "border" + side + "Color"
        const spec = hovered && box.hover && key in box.hover ? box.hover[key] : box[key]
        return spec ? shell.styleColor(spec, shell.foreground) : "transparent"
    }
    readonly property var segments: {
        if (!hasSides) return []
        const c = Math.min(Math.max(radius, topWidth, rightWidth, bottomWidth, leftWidth), width / 2, height / 2)
        const t = topWidth > 0 ? c : 0, b = bottomWidth > 0 ? c : 0
        return [
            topWidth > 0 && { side: "Top", x: 0, y: 0, w: width, h: c, thickness: topWidth },
            rightWidth > 0 && { side: "Right", x: width - c, y: t, w: c, h: height - t - b, thickness: rightWidth },
            bottomWidth > 0 && { side: "Bottom", x: 0, y: height - c, w: width, h: c, thickness: bottomWidth },
            leftWidth > 0 && { side: "Left", x: 0, y: t, w: c, h: height - t - b, thickness: leftWidth }
        ].filter(Boolean)
    }

    visible: hasSides
    anchors.fill: parent
    anchors.topMargin: box ? box.margin[0] : 0
    anchors.rightMargin: box ? box.margin[1] : 0
    anchors.bottomMargin: box ? box.margin[2] : 0
    anchors.leftMargin: box ? box.margin[3] : 0

    Repeater {
        model: root.segments
        delegate: Item {
            id: segment
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            clip: true
            Rectangle {
                x: -parent.x; y: -parent.y; width: root.width; height: root.height
                radius: root.radius; color: "transparent"
                border.color: root.sideColor(segment.modelData.side); border.width: segment.modelData.thickness
            }
        }
    }
}

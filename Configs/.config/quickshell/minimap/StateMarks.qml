pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs

Item {
    id: marks
    property bool pinned: false
    property bool fullscreen: false
    property bool floating: false
    property color ink: "black"
    readonly property real unit: Style.uiScale
    readonly property real edge: 2 * unit
    readonly property real outlineInset: 2.2 * unit
    readonly property real stroke: 1.2 * unit
    readonly property real dot: 4 * unit
    readonly property real arm: Math.max(2 * unit, Math.min(4 * unit, Math.min(width, height) / 3))
    readonly property bool roomy: width >= 10 * unit && height >= 10 * unit
    anchors.fill: parent

    Shape {
        anchors.fill: parent
        visible: marks.roomy && marks.floating && !marks.fullscreen
        ShapePath {
            strokeColor: marks.ink
            strokeWidth: 1.8 * marks.unit
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            startX: marks.outlineInset; startY: marks.outlineInset
            PathLine { x: marks.width - marks.outlineInset; y: marks.outlineInset }
            PathLine { x: marks.width - marks.outlineInset; y: marks.height - marks.outlineInset }
            PathLine { x: marks.outlineInset; y: marks.height - marks.outlineInset }
            PathLine { x: marks.outlineInset; y: marks.outlineInset }
        }
    }
    Repeater {
        model: marks.roomy && marks.fullscreen ? 4 : 0
        Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            Rectangle {
                x: parent.atRight ? marks.width - marks.edge - marks.arm : marks.edge
                y: parent.atBottom ? marks.height - marks.edge - marks.stroke : marks.edge
                width: marks.arm; height: marks.stroke
                color: marks.ink; opacity: 0.9
            }
            Rectangle {
                x: parent.atRight ? marks.width - marks.edge - marks.stroke : marks.edge
                y: parent.atBottom ? marks.height - marks.edge - marks.arm : marks.edge
                width: marks.stroke; height: marks.arm
                color: marks.ink; opacity: 0.9
            }
        }
    }
    Rectangle {
        readonly property bool framed: marks.floating || marks.fullscreen
        visible: marks.roomy && marks.pinned
        x: marks.width - marks.edge - marks.dot * (framed ? 2 : 1)
        y: marks.edge + (framed ? marks.dot : 0)
        width: marks.dot; height: marks.dot; radius: marks.dot / 2
        color: marks.ink; opacity: 0.95
    }
}

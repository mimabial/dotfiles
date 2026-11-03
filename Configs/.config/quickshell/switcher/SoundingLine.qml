pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Depth.js" as Depth
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: gauge

  required property var controller
  required property var theme
  property real unit: 1
  property real textUnit: unit
  property real leadDepth: 0

  readonly property real lineX: 46 * textUnit
  readonly property real lineTop: 22 * unit
  readonly property real lineBottom: height - 8 * unit
  readonly property real markSize: 6 * unit
  readonly property var shown: {
    const list = []
    const controller = gauge.controller
    if (!controller) return list
    for (let i = 0; i < controller.order.length; i++) list.push(controller.field[controller.order[i]])
    return list
  }
  readonly property real markStep: markSize + 2 * unit
  readonly property real marksX: lineX + 8 * unit
  readonly property int maxColumns: Math.max(1, Math.floor((width - marksX - 18 * textUnit) / markStep))
  readonly property var marks: {
    const depths = []
    for (let i = 0; i < shown.length; i++) depths.push(shown[i] ? shown[i].depth : 0)
    return Layout.soundingMarks(depths, lineTop, lineBottom, markSize * 1.3, maxColumns)
  }

  function pick(x, y) {
    if (!gauge.controller || !gauge.marks.length) return
    const column = Math.max(0, Math.round((x - gauge.marksX - gauge.markSize / 2) / gauge.markStep))
    const at = Layout.nearestMark(gauge.marks, y, column)
    const entry = at >= 0 ? gauge.shown[at] : null
    if (entry) gauge.controller.jumpTo(entry.index)
  }

  Text {
    x: gauge.lineX - width / 2
    y: gauge.lineTop - height - 4 * gauge.unit
    color: gauge.theme.textFaint
    font.family: Commons.Style.font.family
    font.pixelSize: 14 * gauge.textUnit
    textFormat: Text.PlainText
    text: "≈"
  }

  Rectangle {
    x: gauge.lineX - width / 2
    y: gauge.lineTop
    width: 1
    height: gauge.lineBottom - gauge.lineTop
    color: gauge.theme.line
  }

  Repeater {
    model: Depth.tickDepths(gauge.controller ? gauge.controller.oldestSeconds : 0)

    delegate: Item {
      id: tick

      required property int index
      required property real modelData

      y: Layout.soundingY(modelData, gauge.lineTop, gauge.lineBottom)

      Rectangle {
        x: gauge.lineX - width / 2
        y: -height / 2
        width: (tick.index % 2 === 0 ? 9 : 5) * gauge.unit
        height: 1
        color: gauge.theme.tick
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: gauge.lineX - 9 * gauge.unit - width
        color: gauge.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 10 * gauge.textUnit
        textFormat: Text.PlainText
        text: Field.depthMarkLabel(tick.modelData, gauge.controller ? gauge.controller.oldestSeconds : 0)
      }
    }
  }

  Repeater {
    model: gauge.marks

    delegate: Rectangle {
      id: mark

      required property var modelData
      required property int index

      readonly property var entry: gauge.shown[index] || null
      readonly property bool selected: gauge.controller !== null && entry !== null && entry.index === gauge.controller.selectedIndex

      x: gauge.marksX + modelData.column * gauge.markStep
      y: modelData.y - height / 2
      width: gauge.markSize
      height: width
      radius: width / 2
      visible: !modelData.hidden
      color: selected ? gauge.theme.accent : (entry && entry.estimated ? "transparent" : gauge.theme.mark)
      border.width: entry && entry.estimated && !selected ? 1 : 0
      border.color: gauge.theme.markBorder

      Text {
        anchors.left: parent.right
        anchors.leftMargin: 3 * gauge.unit
        anchors.verticalCenter: parent.verticalCenter
        visible: mark.modelData.more > 0
        color: gauge.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 9 * gauge.textUnit
        textFormat: Text.PlainText
        text: "+" + mark.modelData.more
      }
    }
  }

  Rectangle {
    x: gauge.lineX - width / 2
    y: gauge.lineTop
    width: 1.5
    height: Math.max(0, Layout.soundingY(gauge.leadDepth, gauge.lineTop, gauge.lineBottom) - gauge.lineTop)
    color: gauge.theme.accent
    visible: gauge.controller !== null && gauge.controller.selectedIndex >= 0
  }

  Rectangle {
    x: gauge.lineX - width / 2
    y: Layout.soundingY(gauge.leadDepth, gauge.lineTop, gauge.lineBottom) - height / 2
    width: 9 * gauge.unit
    height: width
    rotation: 45
    radius: 1.5
    color: gauge.theme.accent
    visible: gauge.controller !== null && gauge.controller.selectedIndex >= 0
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => gauge.pick(mouse.x, mouse.y)
    onPositionChanged: mouse => {
      if (pressed) gauge.pick(mouse.x, mouse.y)
    }
  }
}

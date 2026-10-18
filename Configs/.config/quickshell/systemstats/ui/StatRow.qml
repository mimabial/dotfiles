pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property string label: ""
  property string detail: ""
  property string value: ""
  property string unit: ""
  property color dot: "transparent"
  property bool showDot: dot.a > 0
  property color foreground: Commons.Color.popups.text
  property color valueColor: foreground
  property string fontFamily: Commons.Style.font.family
  property real labelOpacity: 0.85
  property bool boldValue: true
  property real ringValue: -1
  property color ringColor: Commons.Color.accent
  property real rowHeight: Commons.Style.space(20)

  readonly property real dotInset: showDot ? Commons.Style.space(8) + Commons.Style.space(7) : 0
  readonly property real detailInset: detailText.visible ? detailText.implicitWidth + Commons.Style.space(7) : 0
  readonly property real labelBudget: Math.max(0, width - readout.width - Commons.Style.space(10) - dotInset - detailInset)

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(rowHeight, labelText.implicitHeight)
  height: implicitHeight

  Rectangle {
    id: dotMark
    visible: root.showDot
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Commons.Style.space(8)
    height: width
    radius: width / 2
    color: root.dot
  }

  Text {
    id: labelText
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: root.dotInset
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, root.labelBudget)
    text: root.label
    color: root.foreground
    opacity: root.labelOpacity
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.body
    elide: Text.ElideRight
  }

  Text {
    id: detailText
    textFormat: Text.PlainText
    visible: root.detail !== ""
    anchors.left: labelText.right
    anchors.leftMargin: Commons.Style.space(7)
    anchors.verticalCenter: parent.verticalCenter
    text: root.detail
    color: root.foreground
    opacity: Commons.Style.faintTextAlpha
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
  }

  Row {
    id: readout
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.space(8)

    Measure {
      value: root.value
      unit: root.unit
      foreground: root.valueColor
      fontFamily: root.fontFamily
      bold: root.boldValue
      anchors.verticalCenter: parent.verticalCenter
    }

    MiniRing {
      visible: root.ringValue >= 0
      value: root.ringValue
      color: root.ringColor
      foreground: root.foreground
      size: Commons.Style.space(14)
      thickness: Commons.Style.spaceReal(2.2)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}

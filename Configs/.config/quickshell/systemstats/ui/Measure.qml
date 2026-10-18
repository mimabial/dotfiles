pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Row {
  id: root

  property string value: ""
  property string unit: ""
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family
  property real valueSize: Commons.Style.font.body
  property real unitSize: Commons.Style.font.caption
  property bool bold: true
  property real unitOpacity: 0.55
  property real valueOpacity: 1.0

  spacing: (unit === "%" || unit === "°" || unit === "") ? 0 : Commons.Style.space(3)

  Text {
    id: valueText
    textFormat: Text.PlainText
    text: root.value
    color: root.foreground
    opacity: root.valueOpacity
    font.family: root.fontFamily
    font.pixelSize: root.valueSize
    font.bold: root.bold
  }

  Text {
    textFormat: Text.PlainText
    visible: root.unit !== ""
    text: root.unit
    color: root.foreground
    opacity: root.unitOpacity
    font.family: root.fontFamily
    font.pixelSize: root.unitSize
    font.bold: false
    anchors.baseline: valueText.baseline
  }
}

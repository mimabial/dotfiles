pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property string text: ""
  property color color: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  property real letterSize: Commons.Style.spaceReal(10)
  readonly property real capHeightRatio: 0.78
  property real maxHeight: 0
  readonly property real fittedSize: maxHeight > 0 && rows > 0
    ? Math.max(6, Math.min(letterSize, Math.floor(maxHeight / rows / capHeightRatio)))
    : letterSize
  property real rowHeight: Math.round(fittedSize * capHeightRatio)
  property real letterOpacity: 1.0

  readonly property int rows: text.length

  implicitWidth: Math.ceil(metrics.advanceWidth) + 1
  implicitHeight: rows * rowHeight
  width: implicitWidth
  height: implicitHeight

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fittedSize
    font.bold: true
    text: "W"
  }

  Repeater {
    model: root.rows

    delegate: Text {
      required property int index
      y: index * root.rowHeight
      width: root.width
      height: root.rowHeight
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: root.text.charAt(index)
      color: root.color
      opacity: root.letterOpacity
      font.family: root.fontFamily
      font.pixelSize: root.fittedSize
      font.bold: true
      renderType: Text.NativeRendering
    }
  }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  property string value: ""
  property string unit: ""
  property string label: ""
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family
  property int align: Text.AlignHCenter

  spacing: 0

  Item {
    width: parent.width
    height: figure.implicitHeight

    Measure {
      id: figure
      x: root.align === Text.AlignLeft ? 0
        : root.align === Text.AlignRight ? parent.width - width
        : (parent.width - width) / 2
      value: root.value
      unit: root.unit
      foreground: root.foreground
      fontFamily: root.fontFamily
      valueSize: Commons.Style.font.heading
      unitSize: Commons.Style.font.bodySmall
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    horizontalAlignment: root.align
    text: root.label
    color: root.foreground
    opacity: Commons.Style.mutedTextAlpha
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    elide: Text.ElideRight
  }
}

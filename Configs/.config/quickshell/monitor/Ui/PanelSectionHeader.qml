import QtQuick
import qs.Commons as Commons

Text {
  id: root

  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  property real fontSize: Commons.Style.font.caption

  color: Qt.darker(foreground, 1.4)
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true

  topPadding: Math.ceil(fontSize * Commons.Style.glyphOvershoot)
}

pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Text {
  id: root

  property string fontFamily: Commons.Style.font.family

  textFormat: Text.PlainText
  color: Commons.Color.accent
  font.family: fontFamily
  font.pixelSize: Commons.Style.font.caption
  font.bold: true
  font.letterSpacing: 1.1
  font.capitalization: Font.AllUppercase
  elide: Text.ElideRight
  topPadding: Math.ceil(Commons.Style.font.caption * Commons.Style.glyphOvershoot)
}

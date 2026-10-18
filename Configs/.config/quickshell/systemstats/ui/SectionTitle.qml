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
  // Nerd Font outlines overshoot the em box; reserve it so the first row in a
  // clipping list is never beheaded (mirrors qs.Ui.PanelSectionHeader).
  topPadding: Math.ceil(Commons.Style.font.caption * 0.15)
}

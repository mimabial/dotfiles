import QtQuick
import qs.Commons as Commons

Rectangle {
  id: badge
  property string text: ""

  visible: badge.text !== ""
  width: Math.max(badge.height, label.implicitWidth + badge.height / 2)
  radius: badge.height / 2

  Text {
    id: label
    anchors.centerIn: parent
    text: badge.text
    textFormat: Text.PlainText
    color: Commons.Color.bar.background
    font.family: Commons.Style.font.family
    font.pixelSize: Math.round(badge.height * 0.75)
    font.bold: true
  }
}

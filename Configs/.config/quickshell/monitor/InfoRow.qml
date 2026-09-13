pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Item {
  id: infoRow
  required property var controller
  property string label: ""
  property string value: ""
  property bool valueAccent: false
  property bool valueBold: false

  width: parent ? parent.width : 0
  implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

  Text {
    textFormat: Text.PlainText
    id: infoLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(parent.width * 0.34, Style.space(105))
    text: infoRow.label
    color: infoRow.controller.dim
    font.family: infoRow.controller.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  Text {
    textFormat: Text.PlainText
    id: infoValue
    anchors.left: infoLabel.right
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: infoRow.value
    color: infoRow.valueAccent ? Color.accent : infoRow.controller.foreground
    font.family: infoRow.controller.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: infoRow.valueAccent || infoRow.valueBold
    elide: Text.ElideRight
  }
}

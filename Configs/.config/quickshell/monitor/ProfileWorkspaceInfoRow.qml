pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Item {
  id: workspaceInfoRow
  required property var controller
  property string label: ""
  property string displayName: ""
  property string workspaces: ""

  width: parent ? parent.width : 0
  implicitHeight: Math.max(workspaceLabel.implicitHeight, workspaceDisplay.implicitHeight, workspaceValues.implicitHeight)

  Text {
    textFormat: Text.PlainText
    id: workspaceLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(parent.width * 0.34, Commons.Style.space(105))
    text: workspaceInfoRow.label
    color: workspaceInfoRow.controller.dim
    font.family: workspaceInfoRow.controller.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
    elide: Text.ElideRight
  }

  Text {
    textFormat: Text.PlainText
    id: workspaceValues
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: workspaceInfoRow.workspaces
    color: Commons.Color.accent
    font.family: workspaceInfoRow.controller.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    id: workspaceDisplay
    anchors.left: workspaceLabel.right
    anchors.leftMargin: Commons.Style.space(8)
    anchors.right: workspaceValues.left
    anchors.rightMargin: Commons.Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    text: workspaceInfoRow.displayName
    color: workspaceInfoRow.controller.foreground
    font.family: workspaceInfoRow.controller.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
    elide: Text.ElideRight
  }
}

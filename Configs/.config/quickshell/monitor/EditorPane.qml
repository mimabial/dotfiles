import QtQuick
import qs.Commons as Commons
import "Ui"

BorderSurface {
  id: root

  default property alias paneData: content.data
  property string title: ""
  property string meta: ""
  property bool active: false
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family

  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.018)
  borderSpec: Commons.Border.controlSpec(active ? "focus" : "normal", foreground, accent)
  radius: Commons.Style.cornerRadius

  Item {
    id: titleBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Commons.Style.space(10)
    anchors.rightMargin: Commons.Style.space(10)
    height: Commons.Style.space(28)

    Text {
      textFormat: Text.PlainText
      id: titleLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      color: root.active ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - titleLabel.width - Commons.Style.space(12))
      text: root.meta
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: titleBar.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: Commons.Style.space(10)
    anchors.rightMargin: Commons.Style.space(10)
    anchors.bottomMargin: Commons.Style.space(10)
  }
}

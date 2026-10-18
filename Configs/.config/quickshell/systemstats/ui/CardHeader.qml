pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property string title: ""
  property string detail: ""
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(titleText.implicitHeight, detailText.implicitHeight)
  height: implicitHeight

  Text {
    id: titleText
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.title
    color: Commons.Color.accent
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.subtitle
    font.bold: true
    elide: Text.ElideRight
    width: Math.min(implicitWidth, parent.width - detailText.width - Commons.Style.space(8))
  }

  Text {
    id: detailText
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.detail
    color: root.foreground
    opacity: Commons.Style.mutedTextAlpha
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
  }
}

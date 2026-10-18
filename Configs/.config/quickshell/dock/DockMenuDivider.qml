import QtQuick
import qs.Commons as Commons

Item {
  id: mdiv
  readonly property bool isMenuContent: false
  property real menuWidth: 0
  implicitWidth: Commons.Style.space(160)
  width: mdiv.menuWidth > 0 ? mdiv.menuWidth : implicitWidth
  implicitHeight: Math.max(7, Commons.Style.space(7))
  height: Math.max(7, Commons.Style.space(7))

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Commons.Style.space(6)
    anchors.rightMargin: Commons.Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    color: Commons.Util.alpha(Commons.Color.menu.border, 0.45)
  }
}

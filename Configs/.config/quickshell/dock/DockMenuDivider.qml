import QtQuick
import qs.Commons

Item {
  id: mdiv
  readonly property bool isMenuContent: false
  property real menuWidth: 0
  implicitWidth: Style.space(160)
  width: mdiv.menuWidth > 0 ? mdiv.menuWidth : implicitWidth
  implicitHeight: Math.max(7, Style.space(7))
  height: Math.max(7, Style.space(7))

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    color: Util.alpha(Color.menu.border, 0.45)
  }
}

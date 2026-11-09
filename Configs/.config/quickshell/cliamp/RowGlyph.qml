pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Text {
  id: root
  required property var controller
  property color hot: Commons.Color.accent
  property bool lit: false
  property bool navigable: false
  property bool cursored: false
  signal activated()
  function activateKeyboard() { activated() }

  anchors.verticalCenter: parent.verticalCenter
  visible: enabled
  color: lit || mouse.containsMouse || cursored ? hot : controller.dim
  font.family: controller.fontFamily
  font.pixelSize: Commons.Style.font.caption

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Commons.Style.spacing.sm
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}

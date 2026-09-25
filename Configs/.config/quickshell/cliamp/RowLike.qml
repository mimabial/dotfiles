pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// In-row like toggle; state is read off the popup's liked index, never a process.
Text {
  id: root
  required property var controller
  property string url: ""
  property string title: ""
  property string artist: ""
  readonly property bool liked: root.controller.isLiked(root.url, root.title, root.artist)

  z: 2
  anchors.verticalCenter: parent.verticalCenter
  text: root.liked ? "\uec04" : "\ueb05"
  color: root.liked || likeMouse.containsMouse ? root.controller.urgent : root.controller.dim
  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption

  MouseArea {
    id: likeMouse
    anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: root.controller.toggleLikeFor(root.url, root.title, root.artist)
  }
}

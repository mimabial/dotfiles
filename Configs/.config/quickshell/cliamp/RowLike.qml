pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// In-row like toggle; state is read off the popup's liked index, never a process.
Text {
  id: root
  required property var p
  property string url: ""
  property string title: ""
  property string artist: ""
  readonly property bool liked: root.p.isLiked(root.url, root.title, root.artist)

  z: 2
  anchors.verticalCenter: parent.verticalCenter
  text: root.liked ? "\uec04" : "\ueb05"
  color: root.liked || likeMouse.containsMouse ? root.p.urgent : root.p.dim
  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption

  MouseArea {
    id: likeMouse
    anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: root.p.toggleLikeFor(root.url, root.title, root.artist)
  }
}

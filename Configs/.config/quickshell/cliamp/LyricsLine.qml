pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Item {
  id: root
  required property var view
  required property var modelData
  required property int index
  readonly property var popup: view.popup
  readonly property var player: view.player
  readonly property bool isCurrent: index === player.lyricsCurrentIdx
  readonly property bool isPast: player.lyricsCurrentIdx >= 0 && index < player.lyricsCurrentIdx

  width: view.width
  implicitHeight: lyricText.implicitHeight + Commons.Style.space(4)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.modelData.time >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.modelData.time >= 0)
      root.popup.seekTo(Math.max(0, root.modelData.time + root.popup.shell.store.lyricsDelayTenths / 10))
  }

  Text {
    id: lyricText
    anchors.left: parent.left
    anchors.right: parent.right
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: root.modelData.text || "♪"
    color: root.isCurrent ? root.popup.dynamicAccent
      : root.popup.shell.alpha(root.popup.foreground, root.isPast ? 0.28 : 0.65)
    font.family: root.popup.fontFamily
    font.pixelSize: (root.isCurrent ? Commons.Style.font.body : Commons.Style.font.caption) + root.popup.shell.store.lyricsFontStep * 2
    font.bold: root.isCurrent
    Behavior on color { ColorAnimation { duration: 250 } }
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

MediaRow {
  id: row
  required property var modelData
  required property int index
  property string url: modelData.url || ""
  property bool queued: false
  readonly property bool folder: modelData.kind === "dir"
  readonly property bool loading: url !== "" && controller.loadingVid === url
  readonly property bool removable: queued && !isCurrent && controller.queueSource === "cliamp"
  readonly property bool liked: controller.isLiked(url, title, subtitle)

  title: modelData.title || ""
  subtitle: modelData.artist || ""
  thumb: modelData.thumb || ""
  glyph: folder ? "\uf07b" : "\uf001"
  isCurrent: queued ? modelData.current === true
    : !folder && (url !== "" && controller.currentUrl === url || controller.currentTrack === title)
  onActivated: folder ? controller.loadFiles(modelData.rel) : play()

  function play() {
    if (folder) controller.playDir(modelData.rel)
    else if (queued) controller.playQueueItem(modelData)
    else controller.playOrToggle(isCurrent, url, title, subtitle)
  }
  function enqueue() {
    if (folder) controller.queueDir(modelData.rel)
    else if (!queued) controller.queueUrl(url, title, subtitle)
  }
  function dequeue() {
    if (removable) controller.removeFromQueue(modelData.queueIndex)
  }

  RowGlyph {
    controller: row.controller
    enabled: !row.folder
    navigable: enabled
    text: row.liked ? "\uec04" : "\ueb05"
    lit: row.liked
    hot: row.controller.urgent
    onActivated: row.controller.toggleLikeFor(row.url, row.title, row.subtitle)
  }
  RowGlyph {
    controller: row.controller
    enabled: !row.queued || row.removable
    text: row.queued ? "\uf00d" : "\uea60"
    hot: row.queued ? row.controller.urgent : Color.accent
    onActivated: row.queued ? row.dequeue() : row.enqueue()
  }
  Text {
    visible: row.loading
    anchors.verticalCenter: parent.verticalCenter
    text: "\uf110"
    color: Color.accent
    font.family: row.controller.fontFamily
    font.pixelSize: Style.font.caption
    RotationAnimator on rotation { running: row.loading; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
  }
  RowGlyph {
    controller: row.controller
    visible: !row.loading
    text: row.isCurrent && row.controller.isPlaying ? "\uead1" : "\ueb2c"
    lit: row.isCurrent
    onActivated: row.play()
  }
}

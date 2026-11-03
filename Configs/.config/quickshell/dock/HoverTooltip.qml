import QtQuick
import qs.Commons as Commons

DockTooltip {
  id: bubble

  property string text: ""
  property bool hovered: false
  property bool blocked: false
  property bool shown: false

  visible: bubble.shown && bubble.text !== "" && bubble.dock.showTooltips
    && !bubble.blocked && bubble.dock.contextAppId === ""

  onHoveredChanged: {
    if (bubble.hovered) hoverDwellTimer.restart()
    else {
      hoverDwellTimer.stop()
      bubble.shown = false
    }
  }

  onBlockedChanged: if (bubble.blocked) {
    hoverDwellTimer.stop()
    bubble.shown = false
  }

  Timer {
    id: hoverDwellTimer
    interval: bubble.dock.tooltipDelay
    onTriggered: bubble.shown = true
  }

  Text {
    text: bubble.text
    textFormat: Text.PlainText
    color: Commons.Color.tooltip.text
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }
}

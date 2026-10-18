import QtQuick
import qs.Commons as Commons
import qs.Ui

BorderSurface {
  id: bubble
  required property var dock

  property string text: ""
  property bool hovered: false
  property bool blocked: false
  property bool shown: false

  visible: bubble.shown && bubble.text !== "" && bubble.dock.showTooltips
    && !bubble.blocked && bubble.dock.contextAppId === ""
  z: bubble.dock.tooltipZ
  color: Commons.Util.alpha(Commons.Style.popupTinted(Commons.Color.tooltip.background), Commons.Style.popupSurfaceOpacity)
  borderSpec: Commons.Border.surfaceSpec("tooltip", "border", Commons.Style.popupBorder(Commons.Color.tooltip.border), 1)
  radius: Commons.Style.cornerRadius
  padding: Commons.Style.space(4)
  width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
  height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

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
    id: bubbleLabel
    x: bubble.contentLeftInset
    y: bubble.contentTopInset
    width: bubble.width - bubble.contentLeftInset - bubble.contentRightInset
    text: bubble.text
    textFormat: Text.PlainText
    color: Commons.Color.tooltip.text
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }
}

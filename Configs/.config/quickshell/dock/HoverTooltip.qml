import QtQuick
import qs.Commons
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
  z: 300
  color: Util.alpha(Color.tooltip.background, bubble.dock.dockSurfaceOpacity)
  borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
  radius: Style.cornerRadius
  padding: Style.space(4)
  width: bubbleLabel.implicitWidth + contentLeftInset + contentRightInset
  height: bubbleLabel.implicitHeight + contentTopInset + contentBottomInset

  onHoveredChanged: {
    if (bubble.hovered) dwell.restart()
    else {
      dwell.stop()
      bubble.shown = false
    }
  }

  onBlockedChanged: if (bubble.blocked) {
    dwell.stop()
    bubble.shown = false
  }

  Timer {
    id: dwell
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
    color: Color.tooltip.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }
}

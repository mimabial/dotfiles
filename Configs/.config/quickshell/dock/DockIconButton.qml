import QtQuick
import qs.Commons

Item {
  id: btn
  required property var dock
  required property Item card

  property string glyph: ""
  property string tooltip: ""
  property color glyphColor: btn.dock.dockForeground
  // The padded icon box compensates for glyph metrics; this sets optical weight.
  property real glyphSize: btn.dock.iconSize * 0.62
  signal pressed()
  signal middleClicked()
  signal wheelScrolled(int dir)
  signal menuRequested(real x, real y)

  property real homeCenter: 0
  property real magnifyScale: {
    if (btn.dock.waveHover) return btn.dock.magnifyScaleAt(btn.homeCenter)
    if (btn.dock.hoverEffect === "off") return 1
    return area.containsMouse ? btn.dock.zoomPeak : 1
  }

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  readonly property real slotMain: btn.dock.iconSlot * (btn.dock.waveHover ? btn.magnifyScale : 1)
  width: btn.dock.vertical ? btn.dock.iconSlot : btn.slotMain
  height: btn.dock.vertical ? btn.slotMain : btn.dock.iconSlot

  Text {
    anchors.centerIn: parent
    width: btn.dock.iconSize
    height: btn.dock.iconSize
    text: btn.glyph
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    font.family: Style.font.family
    font.pixelSize: btn.glyphSize
    color: area.containsMouse ? Color.accent : btn.glyphColor
    transformOrigin: btn.dock.floorTransformOrigin
    scale: btn.magnifyScale * (area.pressed ? 0.92 : 1.0)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onEntered: btn.dock.slotEntered("__dock_settings__", "")
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var pt = btn.mapToItem(btn.card, btn.width / 2, btn.height / 2)
        var gx = btn.dock.vertical
          ? btn.card.y + (pt ? pt.y : (btn.y + btn.height / 2))
          : btn.card.x + (pt ? pt.x : (btn.x + btn.width / 2))
        btn.menuRequested(gx, 0)
      } else if (mouse.button === Qt.MiddleButton) {
        btn.middleClicked()
      } else {
        btn.pressed()
      }
    }
    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) btn.wheelScrolled(wheel.angleDelta.y > 0 ? -1 : 1)
    }
  }

  HoverTooltip {
    dock: btn.dock
    text: btn.tooltip
    hovered: area.containsMouse
    x: btn.dock.tipX(btn.width, width)
    y: btn.dock.tipY(btn.height, height)
  }
}

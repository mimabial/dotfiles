import QtQuick
import qs.Commons
import ".." as Shell

Item {
  id: btn
  required property var dock

  property string icon: ""
  property string iconContext: ""
  property string tooltip: ""
  signal pressed()
  signal middleClicked()
  signal wheelScrolled(int dir)
  signal menuRequested(real x)

  function trigger(menu) {
    if (menu) btn.menuRequested(btn.dock.slotCenterX(btn))
    else btn.pressed()
  }

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
  width: btn.slotMain
  height: btn.dock.iconSlot

  Shell.SymbolicIcon {
    anchors.centerIn: parent
    name: btn.icon
    context: btn.iconContext
    color: area.containsMouse ? Color.accent : Color.bar.text
    size: btn.dock.iconSize
    transformOrigin: btn.dock.floorTransformOrigin
    scale: btn.magnifyScale * (area.pressed ? 0.92 : 1.0)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onEntered: btn.dock.slotEntered("__dock_settings__", "")
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) btn.middleClicked()
      else btn.trigger(mouse.button === Qt.RightButton)
    }
    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) btn.wheelScrolled(wheel.angleDelta.y > 0 ? -1 : 1)
    }
  }

  HoverTooltip {
    dock: btn.dock
    text: btn.tooltip
    hovered: area.containsMouse
    x: (btn.width - width) / 2
    y: btn.dock.tipY(btn.height, height)
  }
}

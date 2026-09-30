pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "DockModel.js" as DockModel

Item {
  id: item
  required property var dock
  required property var groupData

  function trigger(menu) {
    if (menu) item.dock.openAppGroupContext(item.groupData, item.dock.slotCenterX(item))
    else item.dock.openAppGroup(item.groupData, item.dock.slotCenterX(item))
  }
  property real homeCenter: 0

  readonly property string groupId: String(groupData.id || "")
  readonly property var appIds: DockModel.toArray(groupData.apps)
  readonly property bool isOpen: dock.activeAppGroupId === groupId
  readonly property bool isDropTarget: dock.dropTargetGroupId === groupId
  readonly property var runningInfo: {
    var windows = 0, active = false
    for (var i = 0; i < dock.groupedSection.length; i++) {
      var entry = dock.groupedSection[i]
      if (!entry) continue
      for (var j = 0; j < appIds.length; j++) {
        if (!DockModel.isAppMatch(entry.appId, appIds[j])) continue
        windows += entry.windows || 0
        if (DockModel.isAppMatch(dock.activeId, entry.appId)) active = true
        break
      }
    }
    return { windows: windows, active: active }
  }
  readonly property real slotMain: dock.iconSlot * (dock.waveHover ? magnifyScale : 1)
  width: slotMain
  height: dock.iconSlot

  function iconSource(appId) {
    var entry = dock.appLibrary.lookup(appId) || DockModel.entryFor(dock.appRows, appId)
    return dock.appLibrary.iconSource(entry ? entry.icon : appId)
  }

  property real magnifyScale: {
    if (dock.waveHover) return dock.magnifyScaleAt(homeCenter)
    if (dock.hoverEffect === "off") return 1
    return area.containsMouse ? dock.zoomPeak : 1
  }
  Behavior on magnifyScale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

  Item {
    id: icon
    width: item.dock.iconSize
    height: width
    anchors.centerIn: parent
    scale: item.magnifyScale
    transformOrigin: item.dock.floorTransformOrigin

    Rectangle {
      anchors.fill: parent
      radius: Math.min(width / 4, Style.cornerRadius)
      color: Util.alpha(Color.bar.background, 0.65)
      border.color: item.isDropTarget ? Color.accent : Util.alpha(Color.menu.border, 0.65)
      border.width: item.isDropTarget ? 2 : 1
    }

    Grid {
      anchors.centerIn: parent
      columns: 2
      spacing: Style.space(2)
      Repeater {
        model: item.appIds.slice(0, 4)
        delegate: Image {
          required property var modelData
          width: Math.round(icon.width * 0.36)
          height: width
          source: item.iconSource(modelData)
          sourceSize: Qt.size(width * 2, height * 2)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
        }
      }
    }
  }

  Rectangle {
    visible: item.dock.showIndicators && (item.runningInfo.windows > 0 || item.isOpen)
    readonly property bool emphasized: item.runningInfo.active || item.isOpen
    width: Style.space(emphasized ? 12 : 4)
    height: Style.space(4)
    radius: height / 2
    x: (item.width - width) / 2
    y: item.dock.indicatorY(item.height, height)
    color: emphasized ? Color.bar.active : Util.alpha(Color.bar.text, 0.88)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onEntered: item.dock.slotEntered("__app_group_context__", "", item.groupId)
    onClicked: function(mouse) { item.trigger(mouse.button === Qt.RightButton) }
  }

  HoverTooltip {
    dock: item.dock
    text: String(item.groupData.name || "Applications") + " (" + item.appIds.length + " apps)"
    hovered: area.containsMouse
    blocked: item.dock.activeAppGroupId !== ""
    x: (item.width - width) / 2
    y: item.dock.tipY(item.height, height)
  }
}

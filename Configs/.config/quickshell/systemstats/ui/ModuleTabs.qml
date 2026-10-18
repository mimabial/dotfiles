pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../Model.js" as Model

Item {
  id: root

  property var tabs: []
  property string settingsTab: ""
  property string current: ""
  property int cursorIndex: -1
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family

  signal activated(string id)
  signal hovered(int index, bool isHovered)

  readonly property int count: Array.isArray(tabs) ? tabs.length : 0
  readonly property bool hasSettings: settingsTab !== ""
  readonly property int slots: count + (hasSettings ? 1 : 0)
  readonly property int rows: Math.min(slots, 2)
  readonly property int columns: Math.ceil(slots / 2)
  readonly property real slotWidth: columns > 0 ? width / columns : width
  readonly property real pillHeight: Commons.Style.space(28)
  readonly property real rowGap: Commons.Style.space(4)
  readonly property real labelSize: Commons.Style.font.caption

  readonly property string longestFull: {
    var best = hasSettings ? Model.moduleDef(settingsTab).label : ""
    for (var i = 0; i < count; i++) {
      var label = Model.moduleDef(String(tabs[i])).label
      if (label.length > best.length) best = label
    }
    return best
  }
  readonly property real spelledSlot: Math.ceil(fullMetrics.advanceWidth) + Commons.Style.space(14)
  readonly property real spelledWidth: spelledSlot * columns

  TextMetrics {
    id: fullMetrics
    font.family: root.fontFamily
    font.pixelSize: root.labelSize
    font.bold: true
    text: root.longestFull
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: rows * pillHeight + Math.max(0, rows - 1) * rowGap
  height: implicitHeight

  Repeater {
    model: root.slots

    delegate: Item {
      id: slot
      required property int index
      readonly property bool isSettings: root.hasSettings && index === root.count
      readonly property string tabId: isSettings ? root.settingsTab : String(root.tabs[index] || "")
      readonly property var def: Model.moduleDef(tabId)
      readonly property bool active: root.current === tabId
      readonly property bool hot: root.cursorIndex === index || mouse.containsMouse

      x: index % root.columns * root.slotWidth
      y: Math.floor(index / root.columns) * (root.pillHeight + root.rowGap)
      width: root.slotWidth
      height: root.pillHeight

      Rectangle {
        anchors.centerIn: parent
        width: Math.max(Commons.Style.space(24), root.slotWidth - Commons.Style.space(4))
        height: root.pillHeight
        radius: Commons.Style.cornerRadius
        color: slot.active
          ? Commons.Style.selectedFillFor(root.foreground, Commons.Color.accent)
          : (slot.hot ? Commons.Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent")
        border.width: slot.active ? 1 : 0
        border.color: Commons.Util.alpha(root.foreground, 0.12)

        Behavior on color { ColorAnimation { duration: 90 } }
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: slot.def.label
        width: Math.min(implicitWidth, root.slotWidth - Commons.Style.space(8))
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: root.foreground
        opacity: slot.active || slot.hot ? 1 : 0.7
        font.family: root.fontFamily
        font.pixelSize: root.labelSize
        font.bold: true
        renderType: Text.NativeRendering

        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated(slot.tabId)
        onContainsMouseChanged: root.hovered(slot.index, containsMouse)
      }

    }
  }
}

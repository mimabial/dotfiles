import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: item
  required property var dock
  required property var card

  property string appId: ""
  property string name: ""
  property string icon: ""
  property bool running: false
  property int windows: 0
  property var windowList: []
  // Every window the app owns, parked ones included. They are drawn hollow
  // and labelled [minimized], and the wheel only moves the selection — it is
  // the click that restores, via focusWindowByAddress.
  readonly property var tooltipWindows: windowList || []
  property bool active: false
  property bool pinned: false

  signal activateRequested(string appId)
  signal newWindowRequested(string appId)
  signal menuRequested(string appId, real cx, real cy)
  signal dragStarted(string appId)
  signal dragMoved(string appId, real x)
  signal dragDropped(string appId)
  signal wheelScrolled(string appId, int direction)

  // Only the wave lets a slot grow; zoom keeps the layout still and simply
  // draws its icon larger. Growth is always along the main axis.
  readonly property real slotMain: item.dock.iconSlot * (item.dock.waveHover ? item.magnifyScale : 1)
  width: item.dock.vertical ? item.dock.iconSlot : item.slotMain
  height: item.dock.vertical ? item.slotMain : item.dock.iconSlot

  property bool isDragging: false
  property bool _dragJustEnded: false
  property real dragStartMain: 0
  property real bounceOffset: 0
  property real homeCenter: 0
  property real magnifyScale: {
    if (item.dock.waveHover) return item.dock.magnifyScaleAt(item.homeCenter)
    if (item.dock.hoverEffect === "off") return 1
    return (area.containsMouse && !item.isDragging) ? item.dock.zoomPeak : 1
  }

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  // Live window state. The model carries plain primitives, so anything that
  // must be current — urgency, workspace, parked state — resolves through
  // live handle lookups instead of trusting cached values.

  readonly property bool urgent: {
    if (!item.dock.showUrgentHint) return false
    if (item.active || item.isFocused) return false
    if (item.appId && item.dock.urgentMap[item.appId]) return true
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      var addr = list[i] ? list[i].address : ""
      if (addr && item.dock.urgentMap[addr]) return true
    }
    return false
  }

  readonly property bool minimized: DockModel.allWindowsMinimized(item.windowList, item.dock.liveWsNameOf, item.dock.isMinimizedWorkspace)

  readonly property bool onFocusedWorkspace: {
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      var ws = list[i] ? list[i].workspaceName : ""
      if (ws && (ws === String(item.dock.focusedWorkspaceId) || ws === item.dock.focusedWorkspaceName)) return true
    }
    return false
  }

  // Where a left click would take you, when that is somewhere else.
  readonly property string workspaceHint: {
    if (!item.running || item.minimized || item.onFocusedWorkspace) return ""
    var ws = (item.windowList && item.windowList.length > 0) ? item.windowList[0].workspaceName : ""
    return ws ? DockModel.workspaceShort(ws, ws) : ""
  }

  readonly property bool starting: item.dock.launchPending[item.appId] !== undefined

  // The header is the app's name plus, in brackets, whatever state qualifies
  // it. They are handed out separately so the qualifier can be drawn at lower
  // contrast: it is context, not the thing being named.
  readonly property string tooltipSuffix: {
    if (item.name === "") return ""
    if (item.starting) return "[starting…]"
    if (item.minimized) return "[minimized]"
    if (item.workspaceHint !== "") return "[" + item.workspaceHint + "]"
    return ""
  }

  readonly property string tooltipText: {
    if (item.name === "") return ""
    return item.tooltipSuffix !== "" ? item.name + " " + item.tooltipSuffix : item.name
  }

  // The pulse carries both attention states: urgency, and a launch in
  // progress, where it breathes under the bounce.
  property real pulse: 1.0
  readonly property bool pulsing: item.urgent || item.starting
  onPulsingChanged: if (!item.pulsing) item.pulse = 1.0

  SequentialAnimation on pulse {
    running: item.pulsing
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
    NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
  }

  opacity: item.isDragging ? 0.35 : 1.0
  Behavior on opacity {
    NumberAnimation { duration: 120 }
  }

  readonly property bool bouncing: (item.starting && item.dock.launchBounce) || (item.urgent && item.dock.showUrgentHint)
  onBouncingChanged: if (!item.bouncing) item.bounceOffset = 0

  SequentialAnimation on bounceOffset {
    running: item.bouncing
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: -Style.space(13); duration: 260; easing.type: Easing.OutQuad }
    NumberAnimation { from: -Style.space(13); to: 0; duration: 260; easing.type: Easing.OutBounce }
    PauseAnimation { duration: item.urgent ? 380 : 220 }
  }

  // The icon carries every state on its own: it grows on hover, dips on
  // press, bounces while starting. No plate, no frame — the only chrome in
  // the slot is the running indicator underneath.
  Item {
    id: iconBox
    anchors.fill: parent

    scale: area.pressed ? 0.92 : 1.0
    transformOrigin: item.dock.floorTransformOrigin
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    transform: Translate {
      x: item.dock.vertical ? item.dock.awaySign * item.bounceOffset : 0
      y: item.dock.vertical ? 0 : item.dock.awaySign * item.bounceOffset
    }

    // Sits on the dock floor and grows away from it, so a magnified icon
    // never reaches back over the running dots beneath it.
    Image {
      id: iconImg
      readonly property real floorMargin:
        Math.round(((item.dock.vertical ? iconBox.width : iconBox.height) - item.dock.baseIconArt) / 2)
      x: item.dock.vertical
        ? (item.dock.edge === "left" ? floorMargin : iconBox.width - width - floorMargin)
        : (iconBox.width - width) / 2
      y: item.dock.vertical
        ? (iconBox.height - height) / 2
        : (item.dock.edge === "top" ? floorMargin : iconBox.height - height - floorMargin)
      width: item.dock.baseIconArt * item.magnifyScale
      height: width
      source: {
        var _tv = item.dock.themeVersion
        if (item.icon !== "") return item.icon
        return Quickshell.iconPath("application-x-executable", true)
      }
      sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
      visible: source !== ""
      opacity: item.starting ? (0.4 + 0.6 * item.pulse) : 1.0
      mipmap: true
      smooth: true
    }
  }

  readonly property bool isFocused: {
    if (item.appId && item.dock.activeId && DockModel.isAppMatch(item.appId, item.dock.activeId)) return true
    var list = item.windowList || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].address && list[i].address === item.dock.activeWindowAddress) return true
    }
    return false
  }

  property int selectedWindowIdx: -1

  function isWinMinimized(w) {
    if (!w) return false
    return item.dock.isMinimizedWorkspace(item.dock.liveWsNameOf(w))
  }

  function isWinActive(w) {
    if (!w || !w.address || !item.dock.activeWindowAddress) return false
    return w.address === item.dock.activeWindowAddress
  }

  readonly property int totalWindowCount: (item.windowList && item.windowList.length > 0) ? item.windowList.length : (item.running ? 1 : 0)
  readonly property int maxVisibleDots: totalWindowCount > 5 ? 4 : Math.min(totalWindowCount, 5)
  readonly property real dynamicDotSize: totalWindowCount >= 5 ? Style.space(4) : Style.space(5)
  readonly property real dynamicActiveWidth: totalWindowCount >= 5 ? Style.space(9) : Style.space(12)
  readonly property real dynamicSpacing: totalWindowCount >= 5 ? Style.space(2) : Style.space(3)

  // Fixed on the slot's floor, never scaled or pushed out of the dock.
  Grid {
    id: indicatorRow
    columns: item.dock.vertical ? 1 : Math.max(1, indicatorRow.visibleChildren.length)
    readonly property real floorGap: Style.space(1)
    x: item.dock.vertical
      ? (item.dock.edge === "left" ? floorGap : item.width - width - floorGap)
      : (item.width - width) / 2
    y: item.dock.vertical
      ? (item.height - height) / 2
      : (item.dock.edge === "top" ? floorGap : item.height - height - floorGap)
    spacing: item.dynamicSpacing
    visible: item.running
    z: 2

    Repeater {
      model: item.maxVisibleDots
      delegate: Rectangle {
        readonly property var winObj: (item.windowList && item.windowList.length > index) ? item.windowList[index] : null
        readonly property bool winMinimized: winObj ? item.isWinMinimized(winObj) : item.minimized
        readonly property bool winActive: !winMinimized && (winObj ? item.isWinActive(winObj) : (index === 0 && item.isFocused))

        readonly property real longSide: winActive ? item.dynamicActiveWidth : item.dynamicDotSize
        readonly property real shortSide: winActive ? Style.space(4) : item.dynamicDotSize
        width: item.dock.vertical ? shortSide : longSide
        height: item.dock.vertical ? longSide : shortSide
        radius: Math.min(width, height) / 2

        // 1. Active window: Solid illuminated bar
        // 2. Open visible window: Solid circle
        // 3. Minimized window: Hollow circle (transparent fill with solid border)
        color: winActive
          ? Color.bar.active
          : (winMinimized
              ? "transparent"
              : (item.urgent ? Color.urgent : Util.alpha(item.dock.dockForeground, 0.88)))

        border.color: winActive
          ? Qt.rgba(0, 0, 0, 0.45)
          : (winMinimized
              ? (item.urgent ? Color.urgent : Util.alpha(item.dock.dockForeground, 0.88))
              : Qt.rgba(0, 0, 0, 0.45))

        border.width: winMinimized ? 1.5 : 1

        opacity: item.urgent ? (0.4 + 0.6 * item.pulse) : 1.0

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
      }
    }

    // Compact overflow pill when 6+ windows are open. Wrapped for the same
    // reason as the spine separators: indicatorRow positions its children.
    Item {
      visible: item.totalWindowCount > 5
      width: overflowPill.width
      height: overflowPill.height

      Rectangle {
        id: overflowPill
        anchors.centerIn: parent
        width: overflowText.implicitWidth + Style.space(4)
        height: Style.space(5)
        radius: height / 2
        color: Util.alpha(item.dock.dockForeground, 0.20)
        border.color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1

        Text {
          id: overflowText
          anchors.centerIn: parent
          text: "+" + (item.totalWindowCount - item.maxVisibleDots)
          textFormat: Text.PlainText
          color: item.dock.dockForeground
          font.family: Style.font.family
          font.pixelSize: Math.max(7, Style.font.caption - 4)
          font.bold: true
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onEntered: item.dock.slotEntered(item.appId, "")
    cursorShape: item.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) {
        var dir = wheel.angleDelta.y > 0 ? -1 : 1
        var wins = item.tooltipWindows || []
        if (wins.length > 1) {
          var cur = 0
          if (item.selectedWindowIdx < 0) {
            for (var c = 0; c < wins.length; c++) {
              if (item.dock.isWindowFocused(wins[c])) { cur = c; break; }
            }
            item.selectedWindowIdx = (cur + dir + wins.length) % wins.length
          } else {
            item.selectedWindowIdx = (item.selectedWindowIdx + dir + wins.length) % wins.length
          }

          if (item.dock.contextAppId === item.appId) {
            item.dock.contextSelectedWindowIdx = item.selectedWindowIdx
            return
          }

          itemTooltip.shown = true
        } else {
          item.wheelScrolled(item.appId, dir)
        }
      }
    }

    onPressed: function(mouse) {
      if (mouse.button === Qt.LeftButton && item.pinned) {
        item.dragStartMain = item.dock.vertical ? mouse.y : mouse.x
        item.isDragging = false
        item._dragJustEnded = false
      }
    }

    onPositionChanged: function(mouse) {
      if (area.pressed && mouse.buttons & Qt.LeftButton && item.pinned) {
        var main = item.dock.vertical ? mouse.y : mouse.x
        var dist = Math.abs(main - item.dragStartMain)
        if (!item.isDragging && dist > 8) {
          item.isDragging = true
          item.dragStarted(item.appId)
        }
        if (item.isDragging) {
          var pt = item.mapToItem(item.card, mouse.x, mouse.y)
          item.dragMoved(item.appId, pt ? (item.dock.vertical ? pt.y : pt.x) : main)
        }
      }
    }

    onReleased: function(mouse) {
      if (item.isDragging) {
        item.isDragging = false
        item._dragJustEnded = true
        item.dragDropped(item.appId)
      }
    }

    onCanceled: {
      if (item.isDragging) {
        item.isDragging = false
        item._dragJustEnded = true
        item.dragDropped(item.appId)
      }
    }

    onClicked: function(mouse) {
      if (item._dragJustEnded) {
        item._dragJustEnded = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        var pt = item.mapToItem(item.card, item.width / 2, item.height / 2)
        var gx = item.dock.vertical
          ? item.card.y + (pt ? pt.y : (item.y + item.height / 2))
          : item.card.x + (pt ? pt.x : (item.x + item.width / 2))
        item.menuRequested(item.appId, gx, 0)
      } else if (mouse.button === Qt.MiddleButton) {
        item.newWindowRequested(item.appId)
      } else if (mouse.button === Qt.LeftButton) {
        if (item.dock.contextAppId === item.appId) {
          var chosenIdx = item.selectedWindowIdx
          if (item.dock.contextSelectedWindowIdx >= 0)
            chosenIdx = item.dock.contextSelectedWindowIdx

          if (chosenIdx >= 0 && item.windowList && chosenIdx < item.windowList.length) {
            var chosenWin = item.windowList[chosenIdx]
            if (chosenWin && chosenWin.address) {
              item.dock.focusWindowByAddress(chosenWin.address, item.appId)
            }
          }
          item.selectedWindowIdx = -1
          item.dock.contextSelectedWindowIdx = -1
          item.dock.closeContext()
          return
        }

        if (item.selectedWindowIdx >= 0 && item.tooltipWindows && item.selectedWindowIdx < item.tooltipWindows.length) {
          var chosenWin = item.tooltipWindows[item.selectedWindowIdx]
          if (chosenWin && chosenWin.address) {
            item.dock.focusWindowByAddress(chosenWin.address, item.appId)
          }
          item.selectedWindowIdx = -1
          return
        }
        item.activateRequested(item.appId)
      }
    }
  }

  BorderSurface {
    id: itemTooltip
    property bool shown: false
    readonly property bool wanted: area.containsMouse && !item.isDragging
      && item.name !== "" && item.dock.showTooltips && item.dock.contextAppId === ""
    visible: itemTooltip.shown && itemTooltip.wanted
    z: 300
    color: Util.alpha(Color.tooltip.background, item.dock.dockSurfaceOpacity)
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
    padding: Style.space(6)
    x: item.dock.tipX(item.width, width, Style.space(10))
    y: item.dock.tipY(item.height, height, Style.space(10))
    width: tooltipContent.implicitWidth + contentLeftInset + contentRightInset
    height: tooltipContent.implicitHeight + contentTopInset + contentBottomInset

    onWantedChanged: {
      if (itemTooltip.wanted) tooltipDwell.restart()
      else {
        tooltipDwell.stop()
        itemTooltip.shown = false
        if (item.dock.contextAppId !== item.appId) {
          item.selectedWindowIdx = -1
        }
      }
    }

    Timer {
      id: tooltipDwell
      interval: item.dock.tooltipDelay
      onTriggered: itemTooltip.shown = true
    }

    Column {
      id: tooltipContent
      x: parent.contentLeftInset
      y: parent.contentTopInset
      spacing: Style.space(3)

      Row {
        spacing: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
          text: item.name
          textFormat: Text.PlainText
          color: Color.tooltip.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: item.dock.advancedTooltips && item.running
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: item.tooltipSuffix !== ""
          text: item.tooltipSuffix
          textFormat: Text.PlainText
          // Matches a normal window row below, so the header's qualifier sits
          // at the same weight as the list rather than fading out of it.
          color: Util.alpha(Color.tooltip.text, 0.80)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Repeater {
        model: (item.dock.advancedTooltips && item.tooltipWindows.length > 0)
          ? Math.min(item.tooltipWindows.length, 8) : 0
        delegate: Row {
          spacing: Style.space(5)
          // Window rows run left, so their dots, chevrons and titles line up
          // in columns instead of each row drifting with its own length. The
          // app name above stays centred.
          readonly property bool isSelected: item.selectedWindowIdx === index
          readonly property bool isWinFocused: item.isWinActive(item.tooltipWindows[index])
          readonly property bool isWinParked: item.dock.isWinParkedLive(item.tooltipWindows[index])

          Rectangle {
            width: Style.space(5)
            height: Style.space(5)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            // Hollow when parked, matching the running indicators under the icon.
            color: isWinParked
              ? "transparent"
              : (isSelected ? Color.accent : (isWinFocused ? Color.bar.active : Util.alpha(Color.tooltip.text, 0.5)))
            border.color: isSelected
              ? Color.accent
              : (isWinParked ? Util.alpha(Color.tooltip.text, 0.6) : "transparent")
            border.width: 1
          }

          // Reserved, not prefixed onto the label: putting the chevron in the
          // text re-measured the row on every scroll step, so the tooltip
          // changed width as the selection moved — and the selected row lost
          // two more characters to the 32-char cut than its neighbours.
          Item {
            width: Style.space(6)
            height: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: "›"
              textFormat: Text.PlainText
              opacity: isSelected ? 1 : 0
              font.family: Style.font.family
              font.pixelSize: Math.max(10, Style.font.caption - 1)
              color: Color.accent
            }
          }

          Text {
            text: {
              var w = item.tooltipWindows[index]
              var str = w ? item.dock.windowRowLabel(w) : ""
              return str.length > 32 ? str.slice(0, 30) + "…" : str
            }
            textFormat: Text.PlainText
            color: isSelected
              ? Color.accent
              : (isWinFocused ? Color.tooltip.text : Util.alpha(Color.tooltip.text, 0.80))
            font.family: Style.font.family
            font.pixelSize: Math.max(10, Style.font.caption - 1)
            // Selection deliberately does not bolden: bold is wider, so the
            // row would still grow under the wheel even with the chevron
            // reserved. The chevron, the accent colour and the dot already
            // mark it. Focus does bolden — that does not move while scrolling.
            font.bold: isWinFocused
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }

      Text {
        visible: item.dock.advancedTooltips && item.tooltipWindows.length > 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: "+" + (item.tooltipWindows.length - 8) + " more"
        textFormat: Text.PlainText
        color: Util.alpha(Color.tooltip.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Math.max(9, Style.font.caption - 3)
      }
    }
  }
}

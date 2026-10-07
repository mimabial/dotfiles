pragma ComponentBehavior: Bound
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
  signal menuRequested(string appId, real cx)
  signal dragStarted(string appId)
  signal dragMoved(string appId, real x, bool away)
  signal dragDropped(string appId)
  signal wheelScrolled(string appId, int direction)

  function trigger(menu) {
    if (menu) item.menuRequested(item.appId, item.dock.slotCenterX(item))
    else item.activateRequested(item.appId)
  }

  // Only the wave lets a slot grow; zoom keeps the layout still and simply
  // draws its icon larger. Growth is always along the main axis.
  readonly property real slotMain: item.dock.iconSlot * (item.dock.waveHover ? item.magnifyScale : 1)
  width: item.slotMain
  height: item.dock.iconSlot

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

    transform: Translate { y: item.dock.awaySign * item.bounceOffset }

    // Sits on the dock floor and grows away from it, so a magnified icon
    // never reaches back over the running dots beneath it.
    Image {
      id: iconImg
      x: (iconBox.width - width) / 2
      y: item.dock.edge === "top" ? 0 : iconBox.height - height
      width: item.dock.iconSize * item.magnifyScale
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

      // Sized off the icon, so it grows with magnification like the icon does.
      Rectangle {
        id: badge
        readonly property int count: item.dock.badgeCountFor(item.appId)
        visible: badge.count > 0
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -badge.height / 4
        anchors.rightMargin: -badge.height / 4
        height: Math.round(iconImg.height * 0.4)
        width: Math.max(badge.height, badgeLabel.implicitWidth + badge.height / 2)
        radius: badge.height / 2
        color: Color.urgent

        Text {
          id: badgeLabel
          anchors.centerIn: parent
          text: String(badge.count)
          color: Color.bar.background
          font.family: Style.font.family
          font.pixelSize: Math.round(badge.height * 0.75)
          font.bold: true
        }
      }
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
  readonly property int denseDotThreshold: 5
  readonly property int maxVisibleDots: totalWindowCount > denseDotThreshold ? denseDotThreshold - 1 : Math.min(totalWindowCount, denseDotThreshold)
  readonly property real dynamicDotSize: totalWindowCount >= denseDotThreshold ? Style.space(4) : item.dock.indicatorHeight
  readonly property real dynamicActiveWidth: totalWindowCount >= denseDotThreshold ? Style.space(9) : Style.space(12)
  readonly property real dynamicSpacing: totalWindowCount >= denseDotThreshold ? Style.space(2) : Style.space(3)

  // In the card's floor padding, never scaled with the icon.
  Grid {
    id: indicatorRow
    columns: Math.max(1, indicatorRow.visibleChildren.length)
    x: (item.width - width) / 2
    y: item.dock.indicatorY(item.height, height)
    spacing: item.dynamicSpacing
    visible: item.running && item.dock.showIndicators
    z: 2

    Repeater {
      model: item.maxVisibleDots
      delegate: Rectangle {
        required property int index
        readonly property var winObj: (item.windowList && item.windowList.length > index) ? item.windowList[index] : null
        readonly property bool winMinimized: winObj ? item.isWinMinimized(winObj) : item.minimized
        readonly property bool winActive: !winMinimized && (winObj ? item.isWinActive(winObj) : (index === 0 && item.isFocused))

        width: winActive ? item.dynamicActiveWidth : item.dynamicDotSize
        height: winActive ? Style.space(4) : item.dynamicDotSize
        radius: Math.min(width, height) / 2

        color: winActive
          ? Color.bar.active
          : (winMinimized
              ? "transparent"
              : (item.urgent ? Color.urgent : Util.alpha(Color.bar.text, 0.88)))

        border.color: winActive
          ? Qt.rgba(0, 0, 0, 0.45)
          : (winMinimized
              ? (item.urgent ? Color.urgent : Util.alpha(Color.bar.text, 0.88))
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
      visible: item.totalWindowCount > item.denseDotThreshold
      width: overflowPill.width
      height: overflowPill.height

      Rectangle {
        id: overflowPill
        anchors.centerIn: parent
        width: overflowText.implicitWidth + Style.space(4)
        height: Style.space(5)
        radius: height / 2
        color: Util.alpha(Color.bar.text, 0.20)
        border.color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1

        Text {
          id: overflowText
          anchors.centerIn: parent
          text: "+" + (item.totalWindowCount - item.maxVisibleDots)
          textFormat: Text.PlainText
          color: Color.bar.text
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
          var focusedIndex = 0
          if (item.selectedWindowIdx < 0) {
            for (var index = 0; index < wins.length; index++) {
              if (item.dock.isWindowFocused(wins[index])) { focusedIndex = index; break; }
            }
            item.selectedWindowIdx = (focusedIndex + dir + wins.length) % wins.length
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
      if (mouse.button === Qt.LeftButton) {
        item.dragStartMain = mouse.x
        item.isDragging = false
        item._dragJustEnded = false
      }
    }

    onPositionChanged: function(mouse) {
      if (area.pressed && mouse.buttons & Qt.LeftButton) {
        var main = mouse.x
        var dist = Math.abs(main - item.dragStartMain)
        if (!item.isDragging && dist > 8) {
          item.isDragging = true
          item.dragStarted(item.appId)
        }
        if (item.isDragging) {
          var point = item.mapToItem(item.card, mouse.x, mouse.y)
          var away = !!point && (point.y < -item.dock.iconSlot || point.y > item.card.height + item.dock.iconSlot)
          item.dragMoved(item.appId, point ? point.x : main, away)
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
        item.trigger(true)
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
    z: item.dock.tooltipZ
    color: Util.alpha(Color.tooltip.background, Style.popupSurfaceOpacity)
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius
    padding: Style.space(6)
    x: (item.width - width) / 2
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

    AppTooltipContent {
      id: tooltipContent
      appName: item.name
      suffix: item.tooltipSuffix
      windows: item.tooltipWindows
      advanced: item.dock.advancedTooltips
      selectedIndex: item.selectedWindowIdx
      windowFocused: function(window) { return item.isWinActive(window) }
      windowParked: function(window) { return item.dock.isWinParkedLive(window) }
      windowLabel: function(window) { return item.dock.windowRowLabel(window) }
      x: parent.contentLeftInset
      y: parent.contentTopInset
    }
  }

  HoverTooltip {
    dock: item.dock
    text: "Remove"
    shown: item.isDragging && item.dock.dragRemove
    x: (item.width - width) / 2
    y: item.dock.tipY(item.height, height)
  }
}

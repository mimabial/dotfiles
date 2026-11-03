pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
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

  readonly property real slotMain: item.dock.iconSlot * (item.dock.waveHover ? item.magnifyScale : 1)
  width: item.slotMain
  height: item.dock.iconSlot

  property bool isDragging: false
  property bool _dragJustEnded: false
  property real dragStartMain: 0
  property real dragStartCross: 0
  property point dragOffset: Qt.point(0, 0)
  property real windowTop: 0
  z: item.isDragging ? 1 : 0
  property real liftProgress: item.isDragging ? 1 : 0
  Behavior on liftProgress { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
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
    for (var window of list) {
      var addr = window ? window.address : ""
      if (addr && item.dock.urgentMap[addr]) return true
    }
    return false
  }

  readonly property bool minimized: DockModel.allWindowsMinimized(item.windowList, item.dock.liveWsNameOf, item.dock.isMinimizedWorkspace)

  readonly property bool onFocusedWorkspace: {
    var list = item.windowList || []
    for (var window of list) {
      var ws = window ? window.workspaceName : ""
      if (ws && (ws === String(item.dock.focusedWorkspaceId) || ws === item.dock.focusedWorkspaceName)) return true
    }
    return false
  }

  readonly property string workspaceHint: {
    if (!item.running || item.minimized || item.onFocusedWorkspace) return ""
    var ws = (item.windowList && item.windowList.length > 0) ? item.windowList[0].workspaceName : ""
    return ws ? DockModel.workspaceShort(ws, ws) : ""
  }

  readonly property bool starting: item.dock.launchPending[item.appId] !== undefined

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

  property real pulse: 1.0
  readonly property bool pulsing: item.urgent || item.starting
  onPulsingChanged: if (!item.pulsing) item.pulse = 1.0

  SequentialAnimation on pulse {
    running: item.pulsing
    loops: Animation.Infinite
    NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
    NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
  }

  readonly property bool bouncing: (item.starting && item.dock.launchBounce) || (item.urgent && item.dock.showUrgentHint)
  onBouncingChanged: if (!item.bouncing) item.bounceOffset = 0

  SequentialAnimation on bounceOffset {
    running: item.bouncing
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: -item.dock.bounceHeight; duration: 260; easing.type: Easing.OutQuad }
    NumberAnimation { from: -item.dock.bounceHeight; to: 0; duration: 260; easing.type: Easing.OutBounce }
    PauseAnimation { duration: item.urgent ? 380 : 220 }
  }

  Item {
    id: iconBox
    anchors.fill: parent

    scale: area.pressed ? 0.92 : 1.0
    transformOrigin: item.dock.floorTransformOrigin
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    opacity: item.isDragging ? 0.35 : 1.0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    transform: Translate { y: item.dock.awaySign * item.bounceOffset }

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

      DockBadge {
        id: countBadge
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -height / 4
        anchors.rightMargin: -height / 4
        height: Math.round(iconImg.height * 0.4)
        text: item.launcherEntry && item.launcherEntry.count > 0 ? String(item.launcherEntry.count) : ""
        color: Commons.Color.urgent
      }

      DockBadge {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: -height / 4
        anchors.leftMargin: -height / 4
        height: countBadge.height
        text: item.recording ? "" : item.playing ? "" : ""
        color: item.recording ? Commons.Color.urgent : Commons.Color.bar.active
      }

      Rectangle {
        visible: item.progress !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Commons.Style.space(4)
        height: Commons.Style.space(4)
        radius: height / 2
        color: Commons.Util.alpha(Commons.Color.bar.background, 0.85)

        Rectangle {
          width: parent.width * (item.progress || 0)
          height: parent.height
          radius: parent.radius
          color: Commons.Color.bar.active
        }
      }
    }
  }

  Image {
    readonly property real size: item.dock.iconSize * (1 + (item.dock.zoomPeak - 1) * item.liftProgress)
    readonly property real lift: item.dock.awaySign * item.dock.bounceHeight * item.liftProgress
    visible: item.isDragging
    z: indicatorRow.z + 1
    source: iconImg.source
    sourceSize: iconImg.sourceSize
    width: size
    height: size
    x: (item.width - size) / 2 + item.dragOffset.x
    y: Math.max(-item.windowTop, Math.min(item.Window.height - item.windowTop - size,
      iconImg.y + (iconImg.height - size) / 2 + item.dragOffset.y - lift))
    opacity: item.dock.dragRemove ? 0.5 : 1
    smooth: true
    mipmap: true
  }

  readonly property var launcherEntry: item.dock.launcherEntryFor(item.appId)
  readonly property var progress: item.launcherEntry ? item.launcherEntry.progress : null
  readonly property bool playing: item.dock.appListed(item.dock.playingAppIds, item.appId)
  readonly property bool recording: item.dock.appListed(item.dock.recordingAppIds, item.appId)

  readonly property bool isFocused: {
    if (item.appId && item.dock.activeId && DockModel.isAppMatch(item.appId, item.dock.activeId)) return true
    var list = item.windowList || []
    for (var window of list) {
      if (window && window.address && window.address === item.dock.activeWindowAddress) return true
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
  readonly property real dynamicDotSize: totalWindowCount >= denseDotThreshold ? Commons.Style.space(4) : item.dock.indicatorHeight
  readonly property real dynamicActiveWidth: totalWindowCount >= denseDotThreshold ? Commons.Style.space(9) : Commons.Style.space(12)
  readonly property real dynamicSpacing: totalWindowCount >= denseDotThreshold ? Commons.Style.space(2) : Commons.Style.space(3)

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
        height: winActive ? Commons.Style.space(4) : item.dynamicDotSize
        radius: Math.min(width, height) / 2

        color: winActive
          ? Commons.Color.bar.active
          : (winMinimized
              ? "transparent"
              : (item.urgent ? Commons.Color.urgent : Commons.Util.alpha(Commons.Color.bar.text, 0.88)))

        border.color: winActive
          ? Qt.rgba(0, 0, 0, 0.45)
          : (winMinimized
              ? (item.urgent ? Commons.Color.urgent : Commons.Util.alpha(Commons.Color.bar.text, 0.88))
              : Qt.rgba(0, 0, 0, 0.45))

        border.width: winMinimized ? 1.5 : 1

        opacity: item.urgent ? (0.4 + 0.6 * item.pulse) : 1.0

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
      }
    }

    Item {
      visible: item.totalWindowCount > item.denseDotThreshold
      width: overflowPill.width
      height: overflowPill.height

      Rectangle {
        id: overflowPill
        anchors.centerIn: parent
        width: overflowText.implicitWidth + Commons.Style.space(4)
        height: Commons.Style.space(5)
        radius: height / 2
        color: Commons.Util.alpha(Commons.Color.bar.text, 0.20)
        border.color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1

        Text {
          id: overflowText
          anchors.centerIn: parent
          text: "+" + (item.totalWindowCount - item.maxVisibleDots)
          textFormat: Text.PlainText
          color: Commons.Color.bar.text
          font.family: Commons.Style.font.family
          font.pixelSize: Math.max(7, Commons.Style.font.caption - 4)
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
        item.dragStartCross = mouse.y
        item.isDragging = false
        item._dragJustEnded = false
      }
    }

    onPositionChanged: function(mouse) {
      if (area.pressed && mouse.buttons & Qt.LeftButton) {
        var main = mouse.x
        var dist = Math.abs(main - item.dragStartMain)
        if (!item.isDragging && dist > 8) {
          item.windowTop = item.mapToItem(null, 0, 0).y
          item.isDragging = true
          item.dragStarted(item.appId)
        }
        if (item.isDragging) {
          item.dragOffset = Qt.point(mouse.x - item.dragStartMain, mouse.y - item.dragStartCross)
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

  DockTooltip {
    id: itemTooltip
    dock: item.dock
    target: item
    gap: Commons.Style.space(10)
    padding: Commons.Style.space(6)
    property bool shown: false
    readonly property bool wanted: area.containsMouse && !item.isDragging
      && item.name !== "" && item.dock.showTooltips && item.dock.contextAppId === ""
    visible: itemTooltip.shown && itemTooltip.wanted

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
    }
  }

  HoverTooltip {
    dock: item.dock
    target: item
    text: "Remove"
    shown: item.isDragging && item.dock.dragRemove
  }
}

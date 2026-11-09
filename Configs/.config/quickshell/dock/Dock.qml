pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._Screencopy
import Quickshell.Hyprland
import qs.Commons as Commons
import qs.Ui
import ".." as Shell
import "DockModel.js" as DockModel
import "../PopupNavigation.js" as Navigation

Item {
  id: root

  required property var shell
  readonly property bool dockActive: !["windows", "niri"].includes(root.shell.workflow)
  property alias contextSelectedWindowIdx: contextMenu.selectedWindowIdx
  property alias dockCardItem: dockCard

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/quickshell/dock/pins.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/dock/settings.json"

  property bool blurred: true
  property bool expandBackground: false
  property bool floating: true

  function setBlur(value) {
    root.blurred = value
    root.saveConfig()
  }
  function setExpandBackground(value) {
    root.expandBackground = value
    root.saveConfig()
  }
  function setFloating(value) {
    root.floating = value
    root.saveConfig()
  }
  function setDockEdge(value) {
    root.dockEdge = value
    root.saveConfig()
  }

  readonly property string barEdge: root.shell ? String(root.shell.barEdge) : "top"
  readonly property bool barShown: root.shell ? root.shell.barShown === true || (root.shell.mode === "winbar" && root.shell.prefs.winbarAutoHide) : false
  property string dockEdge: "bottom"
  readonly property string edge: root.barShown
    ? (root.barEdge === "top" ? "bottom" : "top")
    : root.dockEdge
  readonly property int awaySign: root.edge === "bottom" ? 1 : -1
  readonly property int floorTransformOrigin: root.edge === "bottom" ? Item.Bottom : Item.Top
  readonly property real sideGap: root.floating ? root.shell.barFloatGap : 0
  readonly property real edgeGap: root.floating ? Commons.Style.gapsOut : 0
  onEdgeGapChanged: root.updateDockOverlap()

  readonly property real panelGap: Commons.Style.space(6)
  function panelX(width, at) {
    return Math.max(Commons.Style.gapsOut, Math.min(dockWindow.width - width - Commons.Style.gapsOut, at - width / 2))
  }
  function panelY(height) {
    return root.edge === "top" ? dockCard.y + dockCard.height + root.panelGap : dockCard.y - height - root.panelGap
  }
  function parkedSince(address) { return root.parkedAt[address] !== undefined ? root.parkedAt[address] : 0 }
  readonly property int maxGroupTooltipLines: 6

  property string screenName: ""
  readonly property var dockScreen: root.screenForName(root.screenName)
    || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

  function screenForName(name) {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
  }

  function moveToScreen(name) {
    root.screenName = name
    root.saveConfig()
  }

  Variants {
    model: root.dockActive ? Array.prototype.filter.call(Quickshell.screens, screen => screen !== root.dockScreen) : []
    PanelWindow {
      id: followStrip
      required property var modelData
      screen: modelData
      color: "transparent"
      WlrLayershell.namespace: "hypr-shell-dock-follow"
      WlrLayershell.layer: WlrLayer.Top
      exclusionMode: ExclusionMode.Ignore
      anchors {
        top: root.edge === "top"
        bottom: root.edge === "bottom"
        left: true
        right: true
      }
      implicitHeight: root.revealHeight
      HoverHandler { id: push }
      Timer {
        running: push.hovered
        interval: root.revealDelay
        onTriggered: root.moveToScreen(followStrip.modelData.name)
      }
    }
  }

  readonly property AppLibrary appLibrary: AppLibrary { }

  readonly property var magnificationPresets: [{ name: "Subtle", scale: 0.6 }, { name: "Medium", scale: 1 }, { name: "Large", scale: 1.6 }]
  property real magnification: 1
  readonly property real magnifyGrowthPerScale: 0.4
  readonly property real zoomGrowthPerScale: 0.22
  readonly property real magnifyFalloffSlots: 2.2
  readonly property real magnifyPeak: 1 + root.magnifyGrowthPerScale * root.magnification
  readonly property real zoomPeak: 1 + root.zoomGrowthPerScale * root.magnification
  readonly property real magnifyRange: root.iconSlot * root.magnifyFalloffSlots
  readonly property real bounceHeight: Commons.Style.space(13)
  readonly property real magnifiedIconReach: root.iconSize * Math.max(root.magnifyPeak, root.zoomPeak) + root.bounceHeight

  readonly property real pointerMain: cardHover.hovered ? dockCard.x + cardHover.point.position.x : -1e6

  readonly property int appsSlots: root.showAppsButton ? 1 : 0
  readonly property int visibleRunningCount: {
    var count = 0
    for (var item of root.runningSection) {
      if (root.showMinimizedTiles && item && DockModel.allWindowsMinimized(item.windowList, root.liveWsNameOf)) continue
      count++
    }
    return count
  }
  function visibleRunningSlotBefore(idx) {
    var count = 0
    for (var i = 0; i < idx && i < root.runningSection.length; i++) {
      var entry = root.runningSection[i]
      if (!(root.showMinimizedTiles && entry && DockModel.allWindowsMinimized(entry.windowList, root.liveWsNameOf))) count++
    }
    return count
  }
  readonly property bool hasSeparator: (root.pinnedSection.length > 0 || root.hasTiles)
    && root.visibleRunningCount > 0
  readonly property real gapWidth: Math.round(root.iconSize * root.itemSpacing / 32)
  readonly property real separatorWidth: Commons.Style.space(1)
  readonly property int folderSlots: root.pinnedFolders.length + 1
  readonly property bool hasFolderSeparator: root.folderSlots > 0
    && (root.pinnedSection.length > 0 || root.hasTiles || root.visibleRunningCount > 0)

  readonly property var tileModel: {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      return list.map(function (win) { return { type: "single", win: win } })
    }
    var groups = {}
    var order = []
    for (var window of list) {
      var key = window.appId || window.address
      if (!groups[key]) {
        groups[key] = { type: "group", appId: key, title: window.title, windows: [] }
        order.push(key)
      }
      groups[key].windows.push(window)
    }
    order.sort(function (a, b) { return root.parkedSince(groups[a].windows[0].address) - root.parkedSince(groups[b].windows[0].address) })
    return order.map(function (key) { return groups[key] })
  }
  readonly property int tileCount: root.tileModel.length
  readonly property real tileCrossSize: Math.round(root.iconSlot * 0.95)
  readonly property real tileMainSize: Math.round(root.iconSlot * 1.5)

  readonly property real tileRadius: Math.min(Commons.Style.cornerRadius, root.tileCrossSize / 2)
  readonly property bool hasTiles: root.tileCount > 0
  readonly property bool hasLeftTileSeparator: root.hasTiles && (root.pinnedSection.length > 0)

  readonly property int visibleSlotTotal: root.appsSlots + root.pinnedSection.length
    + root.visibleRunningCount + root.folderSlots
  readonly property int appsSeparatorCount: root.appsSlots > 0 && root.visibleSlotTotal + root.tileCount > root.appsSlots ? 1 : 0
  readonly property int elementTotal: root.visibleSlotTotal
    + root.appsSeparatorCount
    + (root.hasSeparator ? 1 : 0)
    + (root.hasFolderSeparator ? 1 : 0)
    + (root.hasLeftTileSeparator ? 1 : 0)
    + (root.hasTiles ? root.tileCount : 0)

  readonly property real baseRowWidth: root.visibleSlotTotal * root.iconSlot
    + root.appsSeparatorCount * root.separatorWidth
    + (root.hasSeparator ? root.separatorWidth : 0)
    + (root.hasFolderSeparator ? root.separatorWidth : 0)
    + (root.hasLeftTileSeparator ? root.separatorWidth : 0)
    + (root.hasTiles ? root.tileCount * root.tileMainSize : 0)
    + Math.max(0, root.elementTotal - 1) * root.gapWidth

  readonly property real baseRowStart: (dockWindow.width
    - (root.baseRowWidth + dockCard.contentLeftInset + dockCard.contentRightInset)) / 2
    + dockCard.contentLeftInset

  function slotHomeCenter(elementIndex, iconSlotsBefore, separatorCount, extraWidth) {
    return root.baseRowStart
      + elementIndex * root.gapWidth
      + iconSlotsBefore * root.iconSlot
      + separatorCount * root.separatorWidth
      + (extraWidth || 0)
      + root.iconSlot / 2
  }

  readonly property real tilesFixedWidth: root.hasTiles
    ? (root.hasLeftTileSeparator ? root.separatorWidth : 0) + root.tileCount * root.tileMainSize
    : 0
  readonly property int tileElements: root.hasTiles ? root.tileCount : 0

  function pinnedHomeCenter(index) {
    var iconsBefore = root.appsSlots + index
    return root.slotHomeCenter(iconsBefore + root.appsSeparatorCount, iconsBefore, root.appsSeparatorCount)
  }
  function tileHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length + index
    var leftSeparator = root.hasLeftTileSeparator ? 1 : 0
    var tileWidthOffset = leftSeparator * root.separatorWidth + index * root.tileMainSize
      + (root.tileMainSize - root.iconSlot) / 2
    return root.slotHomeCenter(iconsBefore + root.appsSeparatorCount + leftSeparator,
      iconsBefore, root.appsSeparatorCount, tileWidthOffset)
  }
  function runningHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length
      + root.visibleRunningSlotBefore(index)
    var separators = root.appsSeparatorCount + (root.hasSeparator ? 1 : 0)
    return root.slotHomeCenter(iconsBefore + separators + (root.hasLeftTileSeparator ? 1 : 0) + root.tileElements,
      iconsBefore, separators, root.tilesFixedWidth)
  }
  function folderHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length
      + root.visibleRunningCount + index
    var separators = root.appsSeparatorCount + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0)
    return root.slotHomeCenter(iconsBefore + separators + (root.hasLeftTileSeparator ? 1 : 0) + root.tileElements,
      iconsBefore, separators, root.tilesFixedWidth)
  }

  function magnifyAt(homeCenter) {
    if (!root.waveHover) return 0
    var distance = root.pointerMain - homeCenter
    if (Math.abs(distance) >= root.magnifyRange) return 0
    return 0.5 * (1 + Math.cos(Math.PI * distance / root.magnifyRange))
  }

  function magnifyScaleAt(homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }

  property int configuredIconSize: 0
  readonly property int iconSize: root.configuredIconSize > 0
    ? root.configuredIconSize
    : Math.max(28, Math.round(Commons.Style.bar.sizeHorizontal * 0.9))
  readonly property int iconSlot: root.iconSize
  readonly property int cardPadding: Math.round(root.iconSize / 8)
  readonly property real indicatorHeight: Commons.Style.space(5)
  readonly property real floorPadding: root.cardPadding + (root.showIndicators ? root.indicatorHeight : 0)
  function indicatorY(hostHeight, height) {
    return root.edge === "top" ? -height - root.cardPadding / 2 : hostHeight + root.cardPadding / 2
  }

  property var pinnedIds: []
  property var appRows: []
  property var dockModel: ({ pinned: [], running: [] })
  property var minimizedWindows: []
  property string minimizedWindowMembership: ""
  readonly property var pinnedSection: root.dockModel.pinned || []
  readonly property var runningSection: root.dockModel.running || []

  readonly property int recentLimit: root.showRecents ? 3 : 0
  property var recentIds: []
  readonly property bool contextIsRecent: root.recentIds.indexOf(root.contextAppId) >= 0

  function buildDockModel(recents) {
    return DockModel.buildEntries(root.pinnedIds,
                                  (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []),
                                  root.appRows, root.appLibrary, root.hyprToplevelFor,
                                  root.minimizedOrigins,
                                  recents, root.recentLimit)
  }

  function rebuildDockModel() {
    var model = root.buildDockModel(root.recentIds)
    var runningIds = model.running.filter(entry => entry.running).map(entry => entry.appId)
    var closedIds = root.runningSection.filter(entry => entry.running && !runningIds.includes(entry.appId)
      && DockModel.exactEntryFor(root.appRows, entry.appId)).map(entry => entry.appId)
    root.dockModel = closedIds.length ? root.buildDockModel(closedIds.concat(root.recentIds)) : model
  }

  function saveRecentApps() {
    var recentIds = root.runningSection.filter(entry => !entry.running).map(entry => entry.appId)
    if (String(recentIds) === String(root.recentIds)) return
    root.recentIds = recentIds
    root.saveConfig()
  }

  property bool completed: false
  Component.onCompleted: {
    root.completed = true
    root.syncDockState()
  }

  function syncDockState() {
    if (!root.completed) return
    root.rebuildDockModel()
    root.saveRecentApps()
    root.rescanMinimizedWindows()
    root.finishLaunches()
    root.pruneWindowState()
    root.updateDockOverlap()
  }

  function rescanMinimizedWindows() {
    var parkedWindows = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var toplevel of tops) {
      if (!toplevel) continue
      var addr = root.windowAddress(toplevel)
      if (!addr) continue
      var isParked = (toplevel.workspace && root.isMinimizedWorkspace(toplevel.workspace.name))
                  || (root.minimizedOrigins && root.minimizedOrigins[addr] !== undefined)
      if (!isParked) continue
      var top = root.liveToplevelForAddress(addr)
      var title = String((top && top.title) || toplevel.title || "Window")
      var appId = ""
      try {
        appId = toplevel.appId ? DockModel.normalizeId(toplevel.appId)
          : (top && top.appId ? DockModel.normalizeId(top.appId) : "")
      } catch (e) {}
      parkedWindows.push({ address: addr, title: title, appId: appId, waylandToplevel: top })
    }
    parkedWindows.sort(function (a, b) { return root.parkedSince(a.address) - root.parkedSince(b.address) })
    var parkedWindowAddresses = parkedWindows.map(function (win) { return win.address }).join(",")
    if (parkedWindowAddresses !== root.minimizedWindowMembership) {
      root.minimizedWindowMembership = parkedWindowAddresses
      root.minimizedWindows = parkedWindows
    }
  }

  readonly property string activeId: {
    try {
      var top = ToplevelManager.activeToplevel
      return top && top.appId ? DockModel.normalizeId(top.appId) : ""
    } catch (e) {
      return ""
    }
  }

  readonly property string activeWindowAddress: {
    try {
      var top = ToplevelManager.activeToplevel
      if (!top) return ""
      var h = root.hyprToplevelFor(top)
      return h ? root.windowAddress(h) : ""
    } catch (e) {
      return ""
    }
  }
  onActiveWindowAddressChanged: root.clearUrgentWindow(root.activeWindowAddress)

  readonly property string dockMonitorName: dockScreen ? String(dockScreen.name || "") : ""
  property string dockSpecialWorkspace: ""
  property bool dockSpecialSeeded: false

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.id
    : -99999

  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace
    ? String(Hyprland.focusedWorkspace.name || Hyprland.focusedWorkspace.id || "")
    : ""

  readonly property int pointerLeaveDelayMs: 350

  function minimizedWorkspaceFor(address) {
    var addr = String(address || "").replace(/^0x/i, "")
    return addr ? DockModel.MINIMIZED_WORKSPACE + "-" + addr : DockModel.MINIMIZED_WORKSPACE
  }

  function isScratchpadWorkspace(name) {
    var value = String(name || "")
    return value.indexOf("special:") === 0 && !root.isMinimizedWorkspace(value)
  }

  function isMinimizedWorkspace(name) {
    return DockModel.isMinimizedWorkspace(name)
  }
  property alias minimizedOrigins: windowState.minimizedOrigins
  property alias parkedAt: windowState.parkedAt
  property alias parkSlots: windowState.parkSlots
  property alias desktopBatches: windowState.desktopBatches
  PersistentProperties {
    id: windowState
    reloadableId: "dock-windows"
    property var minimizedOrigins: ({})
    property var parkedAt: ({})
    property var parkSlots: ({})
    property var desktopBatches: ({})
  }
  readonly property string parkSlotsEvent: "dock-slots>>"
  readonly property string windowsLua: decodeURIComponent(Qt.resolvedUrl("windows.lua").toString().replace(/^file:\/\//, ""))
  property var urgentMap: ({})
  property var recentOpenedWindowAddrs: ({})
  readonly property int openedWindowUrgencyGraceMs: 3000

  property var appRecentWindow: ({})

  property var launchPending: ({})
  readonly property int launchTimeout: 12000

  property string dragAppId: ""
  property bool dragRemove: false
  property string dropBeforeId: ""
  property bool dropIntoPins: false
  property real dropIndicatorMain: 0

  property string contextAppId: ""
  property string contextName: ""
  property bool contextPinned: false
  property int contextWindows: 0
  property var contextWindowList: []
  property string contextDesktopId: ""
  property var contextDesktopActions: []
  property real contextAnchor: 0

  property var pinnedFolders: []
  property string activeStackFolder: ""
  property string activeStackName: ""
  property real activeStackAnchor: 0
  property bool fileDragOut: false
  property string contextFolderPath: ""
  property string contextFolderName: ""

  property bool menuFocusPriming: false
  property int menuCursor: -1
  property var menuRows: []

  function clearMenuCursor() {
    Navigation.setCursor(menuRows, -1)
    menuRows = []
    menuCursor = -1
  }
  function moveMenuCursor(step) {
    var panel = contextAppId !== "" ? contextMenu : folderStack
    var rows = Navigation.collectRows(panel, [])
    menuRows = rows
    if (!rows.length) return
    menuCursor = menuCursor < 0 ? (step > 0 ? 0 : rows.length - 1)
      : (menuCursor + step + rows.length) % rows.length
    Navigation.setCursor(rows, menuCursor)
  }
  function handleMenuKey(event) {
    if (!anyPanelOpen) return dockCursor >= 0 && handleDockKey(event)
    if (activeStackFolder !== "" && folderStack.item && folderStack.item.handleKey(event)) return true
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left) {
      if (contextAppId === "__dock_settings__" && settingsSubmenu !== "") settingsSubmenu = ""
      else if (contextAppId !== "") closeContext()
      else closeFolderStack()
      clearMenuCursor()
      return true
    }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { moveMenuCursor(1); return true }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { moveMenuCursor(-1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space || event.key === Qt.Key_Right) {
      if (menuCursor < 0) moveMenuCursor(1)
      Navigation.activate(menuRows[menuCursor])
      if (!anyPanelOpen) dockCursor = -1
      return true
    }
    return false
  }
  function primeMenuFocus() {
    clearMenuCursor()
    if (!anyPanelOpen) return
    menuKeyCatcher.forceActiveFocus()
    menuFocusPriming = true
    menuFocusTimer.restart()
  }

  property int dockCursor: -1
  readonly property Item dockCursorItem: dockCursor < 0 ? null : dockSlots()[dockCursor] || null
  onDockCursorChanged: { root.syncVisibility(); root.syncPanelDismiss() }
  function dockSlots() {
    return Array.prototype.filter.call(row.children, c => c.visible && c.width > 0 && typeof c.trigger === "function")
  }
  function slotCenterX(item) {
    return dockCard.x + row.x + item.x + item.width / 2
  }
  function moveDockCursor(step) {
    var count = dockSlots().length
    if (count) dockCursor = dockCursor < 0 ? (step > 0 ? 0 : count - 1) : (dockCursor + step + count) % count
  }
  function focusDock() {
    dockCursor = -1
    moveDockCursor(1)
    menuKeyCatcher.forceActiveFocus()
  }
  function handleDockKey(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) moveDockCursor(event.key === Qt.Key_Right ? 1 : -1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      dockCursorItem.trigger(false)
      if (!anyPanelOpen) dockCursor = -1
    }
    else if (event.key === (edge === "top" ? Qt.Key_Down : Qt.Key_Up) || event.key === Qt.Key_Menu) dockCursorItem.trigger(true)
    else if (event.key === Qt.Key_Escape || event.text !== "") dockCursor = -1
    else return false
    return true
  }

  property bool autohide: true
  property bool intelligentAutohide: true
  property bool showAppsButton: true
  property bool showTooltips: true
  property bool showMinimizedTiles: true
  property bool showRecents: true
  property bool showIndicators: true
  property string hoverEffect: "zoom"
  readonly property bool waveHover: root.hoverEffect === "wave"
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0

  readonly property real effectiveDockOpacity: Math.min(1, root.dockOpacity >= 0 ? root.dockOpacity : Commons.Style.barOpacity)
  property int themeVersion: 0
  property string folderColor: "theme"
  readonly property bool symbolicFolders: ["white", "black", "symbolic"].indexOf(root.folderColor) >= 0
  readonly property color symbolicFolderColor: root.folderColor === "white" ? "#ffffff"
    : root.folderColor === "black" ? "#111111" : Commons.Color.bar.text
  property int itemSpacing: 4
  property string minimizeMode: "active"
  readonly property bool clickToMinimize: root.minimizeMode !== "off"
  property bool showUrgentHint: true
  property bool urgentSound: true
  property string urgentSoundName: "bell"
  property int revealDelay: 160
  property int tooltipDelay: 450
  property string settingsSubmenu: ""

  property bool dockVisible: false
  readonly property int revealHeight: 6

  property bool windowsOverlapDock: false
  readonly property var overlapEvents: ["workspace", "workspacev2", "openwindow", "closewindow", "movewindow", "movewindowv2",
    "activewindow", "activewindowv2", "changefloatingmode", "fullscreen", "pin", "focusedmon",
    "togglegroup", "moveintogroup", "moveoutofgroup"]

  Timer {
    id: hideTimer
    interval: root.pointerLeaveDelayMs
    onTriggered: root.dockVisible = false
  }

  Timer {
    id: menuFocusTimer
    interval: Commons.Style.focusPrimeDelay
    onTriggered: root.menuFocusPriming = false
  }

  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: root.dockVisible = true
  }

  Timer {
    id: launchFailureDeadline
    onTriggered: root.finishLaunches()
  }

  function requestDockOverlap() {
    if (root.dockActive && root.autohide && root.intelligentAutohide) Hyprland.refreshToplevels()
  }

  function updateDockOverlap() {
    var clients = []
    var tops = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
    for (const toplevel of tops) {
      var ipc = toplevel ? toplevel.lastIpcObject : null
      if (ipc) clients.push(ipc)
    }

    var dockMonitor = null
    var dockName = dockScreen ? String(dockScreen.name || "") : ""
    if (dockName !== "" && Hyprland.monitors) {
      var monitors = Hyprland.monitors.values || []
      for (var monitor of monitors) {
        if (monitor && String(monitor.name || "") === dockName) {
          dockMonitor = monitor
          break
        }
      }
    }
    if (!dockMonitor) dockMonitor = Hyprland.focusedMonitor
    if (!dockMonitor || !(dockMonitor.width > 0 && dockMonitor.scale > 0) || dockCard.width <= 0) return

    var overlapMargin = 12
    var screenLogicalW = dockMonitor.width / dockMonitor.scale
    var screenLogicalH = dockMonitor.height / dockMonitor.scale
    var footprintWidth = dockCard.width + root.sideGap * 2
    var footprintDepth = dockCard.height + root.edgeGap * 2 + overlapMargin
    var footprintLeft = dockMonitor.x + (screenLogicalW - footprintWidth) / 2
    var footprintRight = dockMonitor.x + (screenLogicalW + footprintWidth) / 2
    var footprintTop = root.edge === "top" ? dockMonitor.y : dockMonitor.y + screenLogicalH - footprintDepth
    var footprintBottom = root.edge === "top" ? dockMonitor.y + footprintDepth : dockMonitor.y + screenLogicalH

    var overlap = false
    var dockWorkspaceId = (dockMonitor && dockMonitor.activeWorkspace) ? dockMonitor.activeWorkspace.id : -1

    if (!root.dockSpecialSeeded && dockMonitor && dockMonitor.lastIpcObject && dockMonitor.lastIpcObject.specialWorkspace) {
      root.dockSpecialWorkspace = String(dockMonitor.lastIpcObject.specialWorkspace.name || "")
      root.dockSpecialSeeded = true
    }
    var dockSpecialWs = root.dockSpecialWorkspace

    for (var client of clients) {
      if (!client.mapped || client.hidden) continue
      if (!client.workspace) continue
      if (client.workspace.id !== dockWorkspaceId
        && !(dockSpecialWs !== "" && String(client.workspace.name || "") === dockSpecialWs)) continue

      var at = client.at
      var size = client.size
      if (!at || !size || at.length < 2 || size.length < 2) continue

      var winLeft = at[0]
      var winTop = at[1]
      var winRight = at[0] + size[0]
      var winBottom = at[1] + size[1]

      var intersectsX = (winRight >= footprintLeft) && (winLeft <= footprintRight)
      var intersectsY = (winBottom >= footprintTop) && (winTop <= footprintBottom)

      if (intersectsX && intersectsY) {
        overlap = true
        break
      }
    }

    root.windowsOverlapDock = overlap
  }

  property var launcherEntries: ({})
  function launcherEntryFor(appId) {
    for (var id in root.launcherEntries)
      if (DockModel.isAppMatch(id, appId)) return root.launcherEntries[id]
    return null
  }
  Process {
    running: true
    command: ["python3", Quickshell.env("HOME") + "/.local/lib/hypr/quickshell/launcher-entry.py"]
    stdout: SplitParser {
      onRead: function(line) {
        var update = JSON.parse(line)
        var next = DockModel.copyMap(root.launcherEntries)
        if (update.count > 0 || update.progress !== null) next[update.app] = update
        else delete next[update.app]
        root.launcherEntries = next
      }
    }
  }

  readonly property var playingAppIds: DockModel.playingAppIds(Shell.Media.players.filter(player => player.isPlaying),
    ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [])
  readonly property var recordingAppIds: Shell.Privacy.microphone.map(node =>
    node.properties["application.process.binary"] || node.properties["application.name"] || "")
  function appListed(ids, appId) { return ids.some(id => DockModel.isAppMatch(id, appId)) }


  function pickCustomFolder() { if (!customFolderPickerProcess.running) customFolderPickerProcess.running = true }

  Process {
    id: customFolderPickerProcess
    command: ["python3", Quickshell.env("HOME") + "/.local/lib/hypr/quickshell/dock-folders.py", "pick"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var chosen = String(this.text || "").trim()
        if (chosen.length > 0) {
          var baseName = chosen.split("/").pop() || "Folder"
          var home = Quickshell.env("HOME")
          var relPath = (chosen.indexOf(home) === 0) ? chosen.replace(home, "~") : chosen
          root.toggleFolderPin(relPath, baseName, DockModel.folderIconFor(relPath, ""))
        }
      }
    }
  }

  readonly property bool pointerOverDock: (cardHover && cardHover.hovered)
    || contextMenu.hovered
    || folderStack.hovered
  readonly property bool anyPanelOpen: root.contextAppId !== "" || root.activeStackFolder !== ""

  onPointerOverDockChanged: root.syncPanelDismiss()
  onAnyPanelOpenChanged: root.syncPanelDismiss()
  onFileDragOutChanged: root.syncPanelDismiss()

  function slotEntered(menuOwner, stackOwner) {
    if (root.dragAppId !== "") return
    root.dockCursor = -1
    if (root.contextAppId !== "" && root.contextAppId !== menuOwner) root.closeContext()
    if (root.activeStackFolder !== "" && root.activeStackFolder !== stackOwner) root.closeFolderStack()
  }

  function syncPanelDismiss() {
    if (root.pointerOverDock || !root.anyPanelOpen || root.dragAppId !== "" || root.dockCursor >= 0 || root.fileDragOut) panelLeaveTimer.stop()
    else panelLeaveTimer.restart()
  }

  Timer {
    id: panelLeaveTimer
    interval: root.pointerLeaveDelayMs
    onTriggered: if (!root.pointerOverDock && root.dragAppId === "") root.closePanels()
  }

  function closePanels() {
    if (root.contextAppId !== "") root.closeContext()
    if (root.activeStackFolder !== "") root.closeFolderStack()
  }

  function syncVisibility() {
    if (!root.dockActive) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = false
      return
    }
    if (!root.autohide) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (cardHover && cardHover.hovered) || (revealHover && revealHover.hovered)
      || root.contextAppId !== "" || root.dragAppId !== "" || root.activeStackFolder !== ""
      || root.dockCursor >= 0

    if (isHovered) {
      hideTimer.stop()
      if (root.dockVisible) revealTimer.stop()
      else if (!revealTimer.running) revealTimer.restart()
      return
    }

    revealTimer.stop()

    if (root.intelligentAutohide && !root.windowsOverlapDock) {
      hideTimer.stop()
      root.dockVisible = true
      return
    }

    if (root.dockVisible) {
      hideTimer.restart()
    }
  }

  onContextAppIdChanged: { root.syncVisibility(); root.primeMenuFocus() }
  onActiveStackFolderChanged: { root.syncVisibility(); root.primeMenuFocus() }
  onSettingsSubmenuChanged: root.clearMenuCursor()
  onDragAppIdChanged: root.syncVisibility()
  onDockActiveChanged: {
    root.requestDockOverlap()
    root.syncVisibility()
  }
  onAutohideChanged: root.syncVisibility()
  onIntelligentAutohideChanged: {
    if (root.intelligentAutohide) root.requestDockOverlap()
    root.syncVisibility()
  }
  onWindowsOverlapDockChanged: root.syncVisibility()
  onDockVisibleChanged: {
    if (!root.dockVisible) {
      root.closeContext()
      root.closeFolderStack()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadConfig()
    onFileChanged: configFile.reload()
  }

  FileView {
    id: dockFile
    path: root.dockPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadPinned()
    onFileChanged: dockFile.reload()
  }

  FileView {
    id: themeIconsFile
    path: Quickshell.env("HOME") + "/.config/hypr/themes/theme.meta"
    watchChanges: true
    printErrors: false
    onLoaded: root.handleThemeChanged()
    onFileChanged: {
      themeIconsFile.reload()
      root.handleThemeChanged()
    }
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.cache/hypr/render/quickshell/theme.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.handleThemeChanged()
    onFileChanged: {
      themeColorsFile.reload()
      root.handleThemeChanged()
    }
  }

  function playUrgentChime() {
    if (!root.urgentSound || root.urgentSoundName === "none") return
    if (!dndProbe.running) dndProbe.running = true
  }

  Process {
    id: dndProbe
    command: ["dunstctl", "is-paused"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (String(this.text || "").trim() === "true") return
        Quickshell.execDetached(["canberra-gtk-play", "-i", root.urgentSoundName])
      }
    }
  }

  Connections {
    target: Commons.Color
    function onShellChanged() { root.handleThemeChanged() }
    function onForegroundChanged() { root.handleThemeChanged() }
    function onAccentChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: Commons.Style
    function onFontFamilyChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rescanApps() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      Qt.callLater(root.syncDockState)
      root.requestDockOverlap()
      root.syncContextWindows()
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      Qt.callLater(root.syncDockState)
    }
  }

  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { Qt.callLater(root.updateDockOverlap) }
      function onWorkspaceChanged() { Qt.callLater(root.syncDockState) }
      function onWaylandHandleChanged() { Qt.callLater(root.syncDockState) }
    }
  }

  Instantiator {
    model: ToplevelManager.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onAppIdChanged() { Qt.callLater(root.syncDockState) }
      function onTitleChanged() { Qt.callLater(root.syncDockState) }
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      try {
        var top = ToplevelManager.activeToplevel
        if (top && top.appId) {
          var activeAppId = DockModel.normalizeId(top.appId)
          var address = root.windowAddress(root.hyprToplevelFor(top))
          if (activeAppId && address) {
            var recent = DockModel.copyMap(root.appRecentWindow)
            recent[activeAppId] = address
            root.appRecentWindow = recent
          }
        }
      } catch (e) {}
      root.requestDockOverlap()
      root.syncContextWindows()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      root.requestDockOverlap()
    }
    function onRawEvent(event) {
      var eventName = String((event && event.name) || "")
      if (eventName === "activespecial") {
        var special = String(event.data || "").split(",")
        var onMonitor = special.length > 1 ? special[special.length - 1].trim() : ""
        if (onMonitor === "" || onMonitor === root.dockMonitorName) {
          root.dockSpecialWorkspace = special[0].trim()
          root.dockSpecialSeeded = true
          root.requestDockOverlap()
        }
      }
      if (eventName === "openwindow") {
        var fullAddr = DockModel.hyprAddress(String(event.data || "").split(",")[0])
        var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
        rec[fullAddr] = Date.now() + root.openedWindowUrgencyGraceMs
        root.recentOpenedWindowAddrs = rec
      }
      if (eventName === "urgent") {
        var fullAddr = DockModel.hyprAddress(event.data)

        var activeAddr = root.windowAddress(root.hyprToplevelFor(ToplevelManager.activeToplevel))
        if (activeAddr && activeAddr === fullAddr) {
          return
        }

        if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr] && Date.now() < root.recentOpenedWindowAddrs[fullAddr]) {
          return
        }

        var allEntries = root.pinnedSection.concat(root.runningSection)
        for (var entry of allEntries) {
          if (!entry) continue
          if (root.launchPending && root.launchPending[entry.id]) {
            var wins = entry.windowList || []
            if (wins.some(function (win) { return win && win.address === fullAddr })) return
          }
        }

        var map = DockModel.copyMap(root.urgentMap)
        map[fullAddr] = true
        root.urgentMap = map
        Qt.callLater(root.syncDockState)
        root.playUrgentChime()
      }
      if (eventName === "activewindowv2")
        root.clearUrgentWindow(DockModel.hyprAddress(String(event.data || "").split(",")[0]))
      if (eventName === "closewindow") {
        var fullAddr = DockModel.hyprAddress(event.data)
        if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr]) {
          var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
          delete rec[fullAddr]
          root.recentOpenedWindowAddrs = rec
        }
        if (root.urgentMap && root.urgentMap[fullAddr]) {
          var map = DockModel.copyMap(root.urgentMap)
          delete map[fullAddr]
          root.urgentMap = map
        }
        if (root.minimizedOrigins && root.minimizedOrigins[fullAddr]) {
          var origins = DockModel.copyMap(root.minimizedOrigins)
          delete origins[fullAddr]
          root.minimizedOrigins = origins
        }
        root.syncDockState()
      }
      var custom = eventName === "custom" ? String(event.data || "") : ""
      if (root.overlapEvents.indexOf(eventName) >= 0 || custom === "layout") root.requestDockOverlap()
      if (custom.indexOf(root.parkSlotsEvent) === 0) root.recordParkSlots(custom.slice(root.parkSlotsEvent.length).split(" "))
      if (eventName === "openwindow" || eventName === "closewindow" || eventName === "urgent"
          || eventName === "movewindow" || eventName === "movewindowv2"
          || eventName === "workspace" || eventName === "workspacev2") Qt.callLater(root.syncDockState)
      if (eventName === "configreloaded") Hyprland.refreshToplevels()
    }
  }

  onShellChanged: root.rescanApps()
  onPinnedIdsChanged: root.syncDockState()
  onShowRecentsChanged: root.syncDockState()

  function loadPinned() {
    root.pinnedIds = DockModel.parsePinned(dockFile.text())
  }

  function loadConfig() {
    var raw = String(configFile.text() || "").trim()
    var parsed = {}
    if (raw) {
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        parsed = {}
      }
    }
    root.autohide = parsed && parsed.autohide !== false
    root.intelligentAutohide = parsed && parsed.intelligentAutohide !== false
    root.showAppsButton = parsed && parsed.showAppsButton !== false
    root.showTooltips = parsed && parsed.showTooltips !== false
    root.showMinimizedTiles = parsed ? parsed.showMinimizedTiles !== false : true
    root.showRecents = parsed ? parsed.showRecents !== false : true
    root.showIndicators = parsed ? parsed.showIndicators !== false : true
    root.magnification = parsed && typeof parsed.magnification === "number" ? parsed.magnification : 1
    root.hoverEffect = parsed && typeof parsed.hoverEffect === "string"
      ? parsed.hoverEffect
      : ((parsed && parsed.magnification === false) ? "off" : "zoom")
    root.launchBounce = parsed && parsed.launchBounce !== false
    root.advancedTooltips = parsed && parsed.advancedTooltips !== false
    root.screenName = parsed && typeof parsed.screen === "string" ? parsed.screen : ""
    root.configuredIconSize = parsed && typeof parsed.iconSize === "number" ? parsed.iconSize : 0
    if (parsed && (parsed.opacity === "theme" || parsed.opacity === "auto" || parsed.opacity === -1)) {
      root.dockOpacity = -1.0
    } else if (parsed && typeof parsed.opacity === "number") {
      root.dockOpacity = Math.max(0.0, Math.min(1.0, parsed.opacity))
    } else {
      root.dockOpacity = 1.0
    }
    root.folderColor = parsed && typeof parsed.folderColor === "string" ? parsed.folderColor : "theme"
    root.dockEdge = parsed && parsed.edge === "top" ? "top" : "bottom"
    root.blurred = parsed ? parsed.blur !== false : true
    root.expandBackground = parsed && parsed.expandBackground === true
    root.floating = parsed && parsed.floating !== false
    root.itemSpacing = parsed && typeof parsed.itemSpacing === "number" ? parsed.itemSpacing : 4
    if (parsed && typeof parsed.minimizeMode === "string") {
      root.minimizeMode = parsed.minimizeMode
    } else if (parsed && parsed.clickToMinimize === true) {
      root.minimizeMode = "active"
    } else {
      root.minimizeMode = "active"
    }
    root.showUrgentHint = parsed ? parsed.showUrgentHint !== false : true
    root.urgentSound = parsed ? parsed.urgentSound !== false : true
    root.urgentSoundName = parsed && typeof parsed.urgentSoundName === "string" ? parsed.urgentSoundName : "bell"
    root.revealDelay = parsed && typeof parsed.revealDelay === "number"
      ? Math.max(0, Math.min(2000, Math.round(parsed.revealDelay)))
      : 160
    root.tooltipDelay = parsed && typeof parsed.tooltipDelay === "number"
      ? Math.max(0, Math.min(5000, Math.round(parsed.tooltipDelay)))
      : 450
    root.recentIds = parsed && Array.isArray(parsed.recentApps) ? parsed.recentApps : []
    if (parsed && Array.isArray(parsed.pinnedFolders)) {
      root.pinnedFolders = parsed.pinnedFolders
    } else {
      root.pinnedFolders = [
        { path: "~/Downloads", name: "Downloads", icon: "folder-download" }
      ]
    }
  }

  function rescanApps() {
    root.appRows = root.appLibrary.entries()
    root.syncDockState()
  }

  function handleThemeChanged() {
    root.themeVersion++
    root.rescanApps()
  }

  function edgeLabel(value) {
    return String(value || "bottom").replace(/^./, function (c) { return c.toUpperCase() })
  }

  function folderColorLabel(colorId) {
    if (!colorId || colorId === "theme" || colorId === "auto") return "Auto (Theme)"
    if (colorId === "white") return "White"
    if (colorId === "black") return "Black"
    if (colorId === "symbolic") return "Symbolic"
    return colorId
  }

  function setFolderColor(color) {
    root.folderColor = color
    root.themeVersion++
    root.saveConfig()
  }

  function openDockSettingsMenu(x) {
    root.contextName = "Dock Settings"
    root.contextWindows = 0
    root.contextWindowList = []
    root.contextPinned = false
    root.contextAnchor = x
    root.settingsSubmenu = ""
    root.contextAppId = "__dock_settings__"
  }

  function setAutohideMode(mode) {
    if (mode === "always") {
      root.autohide = false
      root.intelligentAutohide = false
    } else if (mode === "intelligent") {
      root.autohide = true
      root.intelligentAutohide = true
    } else if (mode === "autohide") {
      root.autohide = true
      root.intelligentAutohide = false
    }
    root.saveConfig()
    root.syncVisibility()
  }

  function setDockOpacity(val) {
    root.dockOpacity = val
    root.saveConfig()
  }

  function setHoverEffect(mode) {
    root.hoverEffect = mode
    root.saveConfig()
  }

  function setIconSize(size) {
    root.configuredIconSize = size
    root.saveConfig()
  }

  function setItemSpacing(sp) {
    root.itemSpacing = sp
    root.saveConfig()
  }

  function setUrgentSoundName(name) {
    root.urgentSoundName = name
    root.urgentSound = name !== "none"
    root.playUrgentChime()
    root.saveConfig()
  }

  function cycleApp(appId, direction) {
    var entry = root.entryForId(appId)
    var next = root.stepWindow(root.visibleWindows(entry ? (entry.windowList || []) : []), direction)
    if (next && next.address) {
      root.focusWindowByAddress(next.address, appId)
      return
    }
    var top = DockModel.pickAppWindow(
      (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), ToplevelManager.activeToplevel, appId, direction)
    if (top) root.focusToplevel(top, appId)
  }

  function hyprToplevelFor(toplevel) {
    if (!toplevel || !Hyprland.toplevels) return null
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].wayland === toplevel) return list[i]
    return null
  }

  function windowAddress(handle) {
    return DockModel.windowAddress(handle)
  }

  function luaString(value) {
    return DockModel.luaString(value)
  }

  function hyprDispatch(lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  function cycleWorkspace(dir) {
    var sel = dir > 0 ? "e+1" : "e-1"
    root.hyprDispatch('hl.dsp.focus({ workspace = "' + sel + '" })',
                      "workspace " + sel)
  }

  function workspaceTarget(workspace) {
    if (!workspace) return ""
    var name = String(workspace.name || "")
    return name !== "" ? name : String(workspace.id)
  }

  function liveToplevelForAddress(addr) {
    if (!addr) return null
    try {
      var tops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var top of tops) {
        if (!top) continue
        var h = root.hyprToplevelFor(top)
        if (root.windowAddress(h) === addr) return top
      }
    } catch (e) {}
    return null
  }

  function liveHyprToplevelForAddress(addr) {
    if (!addr) return null
    try {
      var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
      for (var toplevel of tops) {
        if (toplevel && root.windowAddress(toplevel) === addr) return toplevel
      }
    } catch (e) {}
    return null
  }

  function focusWindowByAddress(addr, appId) {
    if (!addr) return
    var handle = root.liveHyprToplevelForAddress(addr)
    if (handle && handle.workspace && root.isMinimizedWorkspace(handle.workspace.name)) root.restoreWindow(addr, appId)
    else root.focusInPlace(addr)
  }

  function focusToplevel(toplevel, appId) {
    if (!toplevel) return
    var addr = root.windowAddress(root.hyprToplevelFor(toplevel))
    if (addr) root.focusWindowByAddress(addr, appId || DockModel.normalizeId(toplevel.appId || ""))
    else DockModel.focusWindow(toplevel)
  }

  function focusInPlace(address) {
    root.hyprDispatch(root.windowsCall("focus_in_place", ['"' + address + '"']), "focuswindow address:" + address)
  }

  function windowsCall(name, args) {
    return "(function() dofile(" + JSON.stringify(root.windowsLua) + ")." + name + "(" + args.join(", ") + ") return hl.dsp.no_op() end)()"
  }

  function recordParkSlots(fields) {
    var record = {}
    for (var field of fields.slice(1)) {
      var pair = field.split("=")
      record[pair[0]] = pair[1]
    }
    var slots = DockModel.copyMap(root.parkSlots)
    slots[fields[0]] = record
    root.parkSlots = slots
  }

  function returnWindow(address, target, origin) {
    var record = target === origin ? root.parkSlots[address] : undefined
    var slots = DockModel.copyMap(root.parkSlots)
    delete slots[address]
    root.parkSlots = slots
    var recordLua = record
      ? "{" + Object.keys(record).map(owner => '["' + root.luaString(owner) + '"] = "' + root.luaString(record[owner]) + '"').join(", ") + "}"
      : "nil"
    root.hyprDispatch(root.windowsCall("restore", ['"' + address + '"', '"' + root.luaString(target) + '"', recordLua]),
      "movetoworkspacesilent " + target + ",address:" + address)
  }

  function minimizeToplevel(topOrAddr) {
    var address = typeof topOrAddr === "string" ? topOrAddr : root.windowAddress(root.hyprToplevelFor(topOrAddr))
    if (!address) return false

    var handle = root.liveHyprToplevelForAddress(address)
    var origin = (handle && handle.workspace) ? root.workspaceTarget(handle.workspace) : root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!origin || root.isMinimizedWorkspace(origin)) origin = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (root.isMinimizedWorkspace(origin)) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    origins[address] = origin
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    parkedTimes[address] = Date.now()
    root.parkedAt = parkedTimes

    var parkWs = root.minimizedWorkspaceFor(address)
    root.hyprDispatch(root.windowsCall("park", ['"' + address + '"', '"' + root.luaString(parkWs) + '"']),
      "movetoworkspacesilent " + parkWs + ",address:" + address)

    var emptied = root.isScratchpadWorkspace(origin) && origin === root.dockSpecialWorkspace
      && !(Hyprland.toplevels.values || []).some(h => h.workspace && h.workspace.name === origin
        && !root.minimizedOrigins[root.windowAddress(h)])
    if (emptied) {
      var scratchpad = origin.slice("special:".length)
      root.hyprDispatch('hl.dsp.workspace.toggle_special("' + root.luaString(scratchpad) + '")',
        "togglespecialworkspace " + scratchpad)
    }
    return true
  }

  function restoreWindow(targetRef, appId, useOrigin) {
    var address = typeof targetRef === "string" ? targetRef : root.windowAddress(targetRef)
    if (!address) return false

    var origin = root.minimizedOrigins[address] || ""
    var here = root.workspaceTarget(Hyprland.focusedWorkspace)
    var target = (useOrigin || root.isScratchpadWorkspace(origin)) && origin ? origin : here
    if (!target) return false

    var origins = DockModel.copyMap(root.minimizedOrigins)
    delete origins[address]
    root.minimizedOrigins = origins

    var parkedTimes = DockModel.copyMap(root.parkedAt)
    delete parkedTimes[address]
    root.parkedAt = parkedTimes

    if (target !== here) root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                                           "workspace " + target)
    root.returnWindow(address, target, origin)
    root.focusInPlace(address)
    return true
  }

  function restoreWindowBatch(wins, primaryAddress, useOrigin) {
    if (!wins || wins.length === 0) return

    var origins = DockModel.copyMap(root.minimizedOrigins)
    var parkedTimes = DockModel.copyMap(root.parkedAt)

    var focusAddr = null
    var focusTarget = null
    var bestTime = -1
    var here = root.workspaceTarget(Hyprland.focusedWorkspace)

    var latestFirst = wins.filter(window => window && window.address)
      .sort((a, b) => root.parkedSince(b.address) - root.parkedSince(a.address))
    for (var window of latestFirst) {
      var address = window.address

      var origin = origins[address] || ""
      var target = (useOrigin || root.isScratchpadWorkspace(origin)) && origin ? origin : here
      if (!target) continue

      var parkedTime = parkedTimes[address] !== undefined ? parkedTimes[address] : 0
      delete origins[address]
      delete parkedTimes[address]
      root.returnWindow(address, target, origin)

      if (primaryAddress && address === primaryAddress) {
        focusAddr = address
        focusTarget = target
        bestTime = Infinity
      } else if (bestTime !== Infinity && parkedTime >= bestTime) {
        bestTime = parkedTime
        focusAddr = address
        focusTarget = target
      }
    }

    root.minimizedOrigins = origins
    root.parkedAt = parkedTimes

    if (focusTarget) {
      if (focusTarget !== here) root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(focusTarget) + '" })',
                                                  "workspace " + focusTarget)
      root.focusInPlace(focusAddr)
    }
  }

  function toggleDesktop() {
    const workspace = root.workspaceTarget(Hyprland.focusedWorkspace)
    if (!workspace || workspace.startsWith("special:")) return
    const batches = DockModel.copyMap(root.desktopBatches), previous = batches[workspace]
    if (previous) {
      delete batches[workspace]
      root.desktopBatches = batches
      root.restoreWindowBatch(previous.windows.slice().reverse().filter(window => root.isWinParkedLive(window)), previous.focus, true)
      return
    }
    const windows = Array.from(Hyprland.toplevels.values).filter(window =>
      root.workspaceTarget(window.workspace) === workspace && !window.lastIpcObject?.pinned && !window.lastIpcObject?.hidden)
      .map(window => ({ address: root.windowAddress(window) }))
    if (!windows.length) return
    batches[workspace] = { windows, focus: root.activeWindowAddress }
    root.desktopBatches = batches
    for (const window of windows) root.minimizeToplevel(window.address)
  }

  function liveWsNameOf(win) {
    var cached = win ? String(win.workspaceName || "") : ""
    var h = (win && win.address) ? root.liveHyprToplevelForAddress(win.address) : null
    if (h && h.workspace) return String(h.workspace.name || h.workspace.id || "")
    if (win && win.address && root.minimizedOrigins && root.minimizedOrigins[win.address] !== undefined)
      return root.minimizedWorkspaceFor(win.address)
    return cached
  }

  function isWinParkedLive(win) {
    return root.isMinimizedWorkspace(root.liveWsNameOf(win))
  }

  function windowByAddress(windows, address) {
    return DockModel.windowByAddress(windows, address, root.isWinParkedLive)
  }

  function visibleWindows(windows) {
    return DockModel.windowsByParkedState(windows, root.isWinParkedLive, false)
  }

  function focusedIndex(windows) {
    return DockModel.focusedIndex(windows, root.activeWindowAddress)
  }

  function windowHere(windows) {
    return DockModel.windowOnWorkspace(windows, root.liveWsNameOf,
      root.focusedWorkspaceId, root.focusedWorkspaceName)
  }

  function stepWindow(windows, direction) {
    return DockModel.stepWindow(windows, direction, root.activeWindowAddress)
  }

  function parkedWindows(windows) {
    return DockModel.windowsByParkedState(windows, root.isWinParkedLive, true)
  }

  function oldestParked(parked) {
    return DockModel.oldestWindow(parked, root.parkedAt)
  }

  function recentWindow(appId, windows) {
    return root.windowByAddress(windows, root.appRecentWindow[appId])
  }

  function minimizeAllWindows(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var parked = false
    for (var win of windows) {
      if (!win || !win.address) continue
      if (!root.isWinParkedLive(win) && root.minimizeToplevel(win.address))
        parked = true
    }
    return parked
  }

  function minimizeOneWindow(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var target = null

    for (var window of windows) {
      if (window && window.address && window.address === root.activeWindowAddress) {
        target = window
        break
      }
    }
    if (!target) target = root.recentWindow(entry ? entry.appId : "", windows)
    if (!target) {
      for (var window of windows) {
        if (window && !root.isWinParkedLive(window)) {
          target = window
          break
        }
      }
    }

    return (target && target.address) ? root.minimizeToplevel(target.address) : false
  }

  function pruneWindowState() {
    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var toplevel of list) {
      var address = root.windowAddress(toplevel)
      if (address) live[address] = true
    }

    root.minimizedOrigins = root.keepLive(root.minimizedOrigins, live, false)
    root.parkedAt = root.keepLive(root.parkedAt, live, false)
    root.parkSlots = root.keepLive(root.parkSlots, live, false)
    root.appRecentWindow = root.keepLive(root.appRecentWindow, live, true)
    root.urgentMap = root.keepLive(root.urgentMap, live, false)

    var now = Date.now()
    var roa = root.recentOpenedWindowAddrs || {}
    var nextRoa = {}
    var roaChanged = false
    for (var rkey in roa) {
      if (roa[rkey] < now) roaChanged = true
      else nextRoa[rkey] = roa[rkey]
    }
    if (roaChanged) root.recentOpenedWindowAddrs = nextRoa
  }

  function clearUrgentWindow(address) {
    var addr = DockModel.hyprAddress(address)
    if (!addr || !root.urgentMap[addr]) return
    var map = DockModel.copyMap(root.urgentMap)
    delete map[addr]
    root.urgentMap = map
    Qt.callLater(root.syncDockState)
  }

  function keepLive(map, live, addressesAreValues) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var key of keys) {
      if (live[addressesAreValues ? map[key] : key]) next[key] = map[key]
      else dropped = true
    }
    return dropped ? next : map
  }

  IpcHandler {
    target: "dock"

    function minimizeActive(): void {
      var addr = root.activeWindowAddress
      if (addr !== "") root.minimizeToplevel(addr)
    }

    function showDesktop(): void { root.toggleDesktop() }

    function blur(): void { root.setBlur(!root.blurred) }
    function opacity(percent: string): void { root.setDockOpacity(percent === "auto" ? -1 : Number(percent) / 100) }
    function focus(): void { root.focusDock() }
    function reveal(): void { root.dockVisible = true }
    function hide(): void { root.dockVisible = false }
    function toggleVisibility(): void { root.dockVisible = !root.dockVisible }

    function restoreLast(): void {
      var parked = []
      var all = root.pinnedSection.concat(root.runningSection)
      for (var entry of all) {
        if (!entry) continue
        parked = parked.concat(root.parkedWindows(entry.windowList || []))
      }
      if (parked.length > 0) root.restoreWindow(root.oldestParked(parked), "")
    }
  }

  function launchApp(appId, entry) {
    var target = entry || root.entryForId(appId)
    var deskEntry = root.appLibrary.lookup(appId) || DockModel.entryFor(root.appRows, appId)
    var targetId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    if (!root.appLibrary.launch(targetId)) {
      var webAppMatch = String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)__?-(?:default|profile.*)$/i)
                     || String(appId).match(/^(?:chrome|chromium|brave|edge|microsoft-edge)-(.*?)$/i)
      if (webAppMatch) {
        var webDomain = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
        Quickshell.execDetached(["hyprshell", "launch/webapp", "https://" + webDomain])
      }
    }
    root.markLaunching(appId, target ? target.windows : 0)
  }

  function markLaunching(appId, windowsBefore) {
    var pending = DockModel.copyMap(root.launchPending)
    pending[appId] = { deadline: Date.now() + root.launchTimeout, windows: windowsBefore || 0 }
    root.launchPending = pending
    root.finishLaunches()
  }

  function finishLaunches() {
    var now = Date.now()
    var next = {}
    var remaining = 0
    var changed = false

    for (var appId in root.launchPending) {
      var pending = root.launchPending[appId]
      var entry = root.entryForId(appId)
      if ((entry && entry.windows > pending.windows) || now >= pending.deadline) {
        changed = true
        continue
      }
      next[appId] = pending
      remaining++
    }

    if (changed) root.launchPending = next
    launchFailureDeadline.stop()
    if (remaining > 0) {
      launchFailureDeadline.interval = Math.max(0, Math.min(...Object.values(next).map(pending => pending.deadline)) - now)
      launchFailureDeadline.start()
    }
  }

  function saveConfig() {
    var conf = {}
    try {
      var txt = String(configFile.text() || "").trim()
      if (txt) conf = JSON.parse(txt) || {}
    } catch (e) {
      conf = {}
    }
    conf.autohide = root.autohide
    conf.intelligentAutohide = root.intelligentAutohide
    conf.showAppsButton = root.showAppsButton
    conf.showTooltips = root.showTooltips
    conf.showMinimizedTiles = root.showMinimizedTiles
    conf.showRecents = root.showRecents
    conf.showIndicators = root.showIndicators
    conf.magnification = root.magnification
    conf.hoverEffect = root.hoverEffect
    delete conf.magnification
    conf.launchBounce = root.launchBounce
    conf.advancedTooltips = root.advancedTooltips
    if (root.screenName) conf.screen = root.screenName
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity < 0 ? "theme" : root.dockOpacity
    conf.folderColor = root.folderColor
    conf.edge = root.dockEdge
    conf.blur = root.blurred
    conf.expandBackground = root.expandBackground
    conf.floating = root.floating
    conf.itemSpacing = root.itemSpacing
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.pinnedFolders = root.pinnedFolders
    conf.recentApps = root.recentIds
    configFile.setText(JSON.stringify(conf, null, 2))
  }

  function activate(appId) {
    var entry = root.entryForId(appId)
    var windows = entry ? (entry.windowList || []) : []
    if (!entry || !entry.running || windows.length === 0) {
      root.launchApp(appId, entry)
      return
    }

    var visible = root.visibleWindows(windows)
    var parked = root.parkedWindows(windows)
    var focusedIdx = root.focusedIndex(visible)

    function isUrgent(win) { return !!win && !!win.address && !!root.urgentMap[win.address] }
    var urgentWin = visible.find(isUrgent) || null
    var urgentParked = parked.find(isUrgent) || null

    if (urgentParked) {
      root.restoreWindow(urgentParked.address || urgentParked, appId)
      return
    }

    if (urgentWin) {
      root.focusWindowByAddress(urgentWin.address, appId)
      return
    }

    if (focusedIdx >= 0) {
      if (root.minimizeMode === "all") {
        root.minimizeAllWindows(entry)
        return
      }
      if (root.minimizeMode === "active") {
        if (visible[focusedIdx] && visible[focusedIdx].address) {
          root.minimizeToplevel(visible[focusedIdx].address)
        } else {
          root.minimizeOneWindow(entry)
        }
        return
      }
      if (visible.length > 1) {
        var next = root.stepWindow(visible, 1)
        if (next && next.address) root.focusWindowByAddress(next.address, appId)
        return
      }
      return
    }

    if (visible.length > 0) {
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
    } else if (parked.length > 0) {
      root.restoreWindow(root.oldestParked(parked), appId)
    }
  }

  readonly property bool selectedContextWindowParked: {
    var wins = root.contextWindowList || []
    var idx = -1
    try { idx = contextMenu.selectedWindowIdx } catch (e) { idx = -1 }
    if (idx < 0 || idx >= wins.length) return false
    return root.isWinParkedLive(wins[idx])
  }

  function workspaceLabel(name) {
    return DockModel.workspaceLabel(name)
  }

  function windowRowLabel(window) {
    var title = String((window && window.title) || "Window")
    var wsName = root.liveWsNameOf(window)
    var origin = (window && window.address && root.minimizedOrigins)
      ? String(root.minimizedOrigins[window.address] || "") : ""
    var label = root.workspaceLabel(root.isMinimizedWorkspace(wsName) ? origin : wsName)
    return label !== "" ? "[" + label + "] " + title : title
  }

  function entryForId(appId) {
    var i
    for (i = 0; i < root.pinnedSection.length; i++) {
      if (root.pinnedSection[i].appId === appId || DockModel.isAppMatch(root.pinnedSection[i].appId, appId))
        return root.pinnedSection[i]
    }
    for (i = 0; i < root.runningSection.length; i++) {
      if (root.runningSection[i].appId === appId || DockModel.isAppMatch(root.runningSection[i].appId, appId))
        return root.runningSection[i]
    }
    return null
  }

  function setPinned(next) {
    root.pinnedIds = next
    dockFile.setText(DockModel.serializePinned(next))
  }

  function togglePin(appId) {
    root.setPinned(DockModel.togglePinned(root.pinnedIds, appId))
  }

  function removeRecent(appId) {
    root.recentIds = root.recentIds.filter(id => id !== appId)
    root.saveConfig()
    root.syncDockState()
  }

  function launchDesktopAction(action, appName) {
    if (!action) return
    root.markLaunching(root.contextAppId || "", 0)
    try {
      if (typeof action.execute === "function") {
        action.execute()
        return
      }
    } catch (e) {}

    try {
      if (action.command && action.command.length > 0) {
        Quickshell.execDetached(action.command)
      }
    } catch (e2) {}
  }

  function isWindowFocused(win) {
    if (!win || !win.address || !root.activeWindowAddress) return false
    return win.address === root.activeWindowAddress
  }

  function isWindowParked(win) {
    if (!win) return false
    return root.isWinParkedLive(win)
  }

  function syncContextWindows() {
    if (!root.contextAppId || root.contextAppId.indexOf("__") === 0) return
    var entry = root.entryForId(root.contextAppId)
    var wins = entry && entry.windowList ? entry.windowList : []
    if (wins.length === 0) {
      var allTops = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
      for (var top of allTops) {
        if (top && (top.appId === root.contextAppId || DockModel.isAppMatch(top.appId, root.contextAppId))) {
          var h = root.hyprToplevelFor ? root.hyprToplevelFor(top) : null
          var addr = root.windowAddress(h)
          var ws = h ? h.workspace : null
          var wsName = ws ? String(ws.name || ws.id || "") : (addr && root.minimizedOrigins && root.minimizedOrigins[addr] ? root.minimizedWorkspaceFor(addr) : "")
          var isParked = root.isMinimizedWorkspace(wsName) || Boolean(addr && root.minimizedOrigins && root.minimizedOrigins[addr])
          wins.push({
            title: String(top.title || "Window"),
            address: addr,
            appId: String(top.appId),
            workspaceName: isParked ? root.minimizedWorkspaceFor(addr) : wsName,
            isMinimized: isParked
          })
        }
      }
    }
    root.contextWindowList = wins
    root.contextWindows = wins.length
    try {
      if (contextMenu.selectedWindowIdx >= wins.length) {
        contextMenu.selectedWindowIdx = -1
      }
    } catch (e) {}
  }

  function openContext(appId, x) {
    root.contextAppId = appId
    var entry = root.entryForId(appId)
    root.contextName = entry ? entry.name : appId
    root.syncContextWindows()

    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    }
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextPinned = DockModel.isPinned(root.pinnedIds, appId) || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextDesktopId = deskEntry && deskEntry.id ? String(deskEntry.id) : ""
    root.contextDesktopActions = (deskEntry && deskEntry.actions) ? deskEntry.actions : []
    try { contextMenu.selectedWindowIdx = -1 } catch (e) {}
    root.contextAnchor = x
  }

  function closeContext() {
    root.contextAppId = ""
    root.syncVisibility()
  }

  property var contextTileWins: []
  property string contextTileAppId: ""
  property string contextTileName: ""
  property bool contextTilePinned: false

  function openTileContext(wins, appId, cx) {
    root.contextTileWins = wins || []
    root.contextTileAppId = appId || ""
    var deskEntry = DockModel.entryFor(root.appRows, appId)
    if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries)
      deskEntry = DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId)
    root.contextTileName = (deskEntry && deskEntry.name) ? deskEntry.name : appId
    var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : appId
    root.contextTilePinned = DockModel.isPinned(root.pinnedIds, appId)
      || (canonicalId !== appId && DockModel.isPinned(root.pinnedIds, canonicalId))
    root.contextAnchor = cx
    root.contextAppId = "__tile_context__"
    root.syncVisibility()
  }

  function restoreContextTile() {
    root.restoreWindowBatch(root.contextTileWins || [])
  }

  function restoreContextTileOriginal() {
    root.restoreWindowBatch(root.contextTileWins || [], null, true)
  }

  function closeContextTile() {
    var wins = root.contextTileWins
    for (var window of wins) {
      if (window && window.address) root.hyprDispatch(
        'hl.dsp.window.close({ window = "address:' + window.address + '" })',
        "closewindow address:" + window.address)
    }
  }

  function openFolderStack(path, name, cx) {
    if (root.activeStackFolder === path) {
      root.closeFolderStack()
      return
    }
    root.closeContext()
    root.closeFolderStack()
    root.activeStackFolder = path
    root.activeStackName = name || "Folder"
    root.activeStackAnchor = cx
    root.syncVisibility()
  }

  function closeFolderStack() {
    root.activeStackFolder = ""
    root.activeStackName = ""
    root.syncVisibility()
  }

  FolderListModel {
    id: trashFiles
    folder: "file://" + (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"
    showHidden: true
  }
  readonly property bool trashFull: trashFiles.count > 0

  function openTrash() {
    root.openInFileManager("trash:///")
  }

  function openInFileManager(target) {
    fileManagerLookup.target = root.expandHome(target)
    fileManagerLookup.running = true
  }

  Process {
    id: fileManagerLookup
    property string target: ""
    command: ["xdg-mime", "query", "default", "inode/directory"]
    stdout: StdioCollector {
      onStreamFinished: {
        Quickshell.execDetached(["uwsm-app", "--", "gio", "open", fileManagerLookup.target])
        var fileManager = DockModel.pickAppWindow(ToplevelManager.toplevels ? ToplevelManager.toplevels.values : [], null, this.text.trim(), 1)
        if (fileManager) root.focusToplevel(fileManager, "")
      }
    }
  }

  function forceQuit(windows) {
    for (var win of windows)
      if (win.address) root.hyprDispatch('hl.dsp.window.kill({ window = "address:' + win.address + '" })',
        "killwindow address:" + win.address)
  }

  readonly property string autostartDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/autostart"
  FolderListModel {
    id: autostartFiles
    folder: "file://" + root.autostartDir
    nameFilters: ["*.desktop"]
    showDirs: false
  }
  readonly property string contextAutostartFile: root.contextDesktopId
    ? root.autostartDir + "/" + DockModel.stripDesktop(root.contextDesktopId) + ".desktop"
    : ""
  readonly property bool contextOpensAtLogin: autostartFiles.count > 0 && root.contextAutostartFile !== ""
    && autostartFiles.indexOf("file://" + root.contextAutostartFile) >= 0

  function toggleOpenAtLogin() {
    if (root.contextOpensAtLogin) Quickshell.execDetached(["rm", "-f", root.contextAutostartFile])
    else Quickshell.execDetached(["sh", "-c",
      'for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(printf %s "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr : " "); do'
      + ' f="$d/applications/${1##*/}"; [ -f "$f" ] && mkdir -p "${1%/*}" && exec ln -sf "$f" "$1"; done',
      "sh", root.contextAutostartFile])
  }

  function openTrashContext(cx) {
    root.closeFolderStack()
    root.contextAnchor = cx
    root.contextAppId = "__trash_context__"
    root.syncVisibility()
  }

  function openFolderContext(path, name, cx) {
    root.closeFolderStack()
    root.contextFolderPath = path
    root.contextFolderName = name || "Folder"
    root.contextAnchor = cx
    root.contextAppId = "__folder_context__"
    root.syncVisibility()
  }

  function expandHome(path) {
    return String(path || "").replace(/^~/, Quickshell.env("HOME"))
  }

  function isFolderPinned(path) {
    var norm = root.expandHome(path)
    return (root.pinnedFolders || []).some(folder => root.expandHome(folder.path) === norm)
  }

  function toggleFolderPin(path, name, icon) {
    var next = []
    var found = false
    var norm = root.expandHome(path)
    var list = root.pinnedFolders || []
    for (var folder of list) {
      if (root.expandHome(folder.path) === norm) {
        found = true
      } else {
        next.push(folder)
      }
    }
    if (!found) {
      next.push({ path: path, name: name || "Folder", icon: icon || DockModel.folderIconFor(path, "") })
    }
    root.pinnedFolders = next
    root.saveConfig()
  }

  function itemMainBounds(item) {
    var point = item.mapToItem(dockCard, 0, 0)
    return { start: point.x, size: item.width }
  }

  function updateDragTarget(appId, main, away) {
    root.dropBeforeId = ""
    root.dropIntoPins = false
    root.dragRemove = !!away && (DockModel.isPinned(root.pinnedIds, appId) || root.recentIds.indexOf(appId) >= 0)
    if (root.dragRemove) return

    var count = pinnedRepeater.count
    if (count === 0) return

    var first = root.itemMainBounds(pinnedRepeater.itemAt(0))
    var last = root.itemMainBounds(pinnedRepeater.itemAt(count - 1))
    root.dropIntoPins = main >= first.start - root.gapWidth && main <= last.start + last.size + root.gapWidth
    if (!root.dropIntoPins && root.pinnedIds.indexOf(appId) < 0) return

    for (var pinIndex = 0; pinIndex < count; pinIndex++) {
      var pin = pinnedRepeater.itemAt(pinIndex)
      var pinBounds = root.itemMainBounds(pin)
      if (main < pinBounds.start + pinBounds.size / 2) {
        root.dropBeforeId = root.pinnedSection[pinIndex].appId
        root.dropIndicatorMain = pinBounds.start - Commons.Style.space(1)
        return
      }
    }
    root.dropIndicatorMain = last.start + last.size + Commons.Style.space(1)
  }

  function finishDrag() {
    var appId = root.dragAppId
    var before = root.dropBeforeId
    var pinHere = root.dropIntoPins
    var remove = root.dragRemove

    root.dragAppId = ""
    root.dragRemove = false
    root.dropBeforeId = ""
    root.dropIntoPins = false
    if (!appId) return
    if (remove) {
      if (root.recentIds.indexOf(appId) >= 0) root.removeRecent(appId)
      else root.setPinned(root.pinnedIds.filter(id => id !== appId))
      return
    }

    if (pinHere || root.pinnedIds.indexOf(appId) >= 0) {
      var pins = root.pinnedIds.slice()
      if (pins.indexOf(appId) < 0) pins.push(appId)
      root.setPinned(DockModel.reorderPinned(pins, appId, before))
    }
  }

  function menuContentWidth(item) {
    var widest = 0
    if (!item) return widest

    var kids = item.children
    for (var child of kids) {
      if (!child || !child.visible) continue
      if (child.isMenuContent === true && child.implicitWidth > widest) widest = child.implicitWidth
      var nested = root.menuContentWidth(child)
      if (nested > widest) widest = nested
    }
    return Math.min(Math.max(widest, Commons.Style.space(220)), Commons.Style.space(280))
  }

  Shell.LayerBlur { surface: "hypr-shell-dock"; enabled: root.blurred && root.dockActive; ignoreAlpha: 0.1 }

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    visible: root.dockActive
    color: "transparent"
    WlrLayershell.namespace: "hypr-shell-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.dockCursor >= 0 ? WlrKeyboardFocus.Exclusive
      : !root.anyPanelOpen ? WlrKeyboardFocus.None
      : root.menuFocusPriming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide)
      ? Math.round(dockCard.height + root.edgeGap)
      : 0

    anchors {
      top: root.edge !== "bottom"
      bottom: root.edge !== "top"
      left: true
      right: true
    }
    implicitHeight: dockCard.height + root.edgeGap + root.magnifiedIconReach
    Item {
      id: menuKeyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: event => event.accepted = root.handleMenuKey(event)
      Window.onActiveChanged: if (!Window.active) root.dockCursor = -1
    }

    mask: Region {
      x: dockCard.x
      y: dockCard.y
      width: dockCard.width
      height: dockCard.height
      regions: [
        Region { item: revealStrip },
        Region { item: globalDismiss }
      ]
    }

    Item {
      id: revealStrip
      width: parent.width
      height: root.revealHeight
      y: root.edge === "bottom" ? parent.height - height : 0

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      Rectangle {
        visible: root.autohide
        x: (parent.width - width) / 2
        y: root.edge === "top" ? 0 : parent.height - height
        width: revealHover.hovered ? Commons.Style.space(48) : Commons.Style.space(24)
        height: Commons.Style.space(3)
        radius: height / 2
        color: Commons.Util.scaleAlpha(Commons.Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
        Behavior on width { NumberAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }

    Item {
      id: globalDismiss
      width: root.anyPanelOpen ? dockWindow.width : 0
      height: root.anyPanelOpen ? dockWindow.height : 0
      MouseArea {
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.closePanels()
        onReleased: function(mouse) {
          if (root.dragAppId !== "") root.finishDrag()
        }
      }
    }

    BorderSurface {
      id: dockCard

      color: Commons.Util.scaleAlpha(Commons.Color.bar.background, root.effectiveDockOpacity)
      borderSpec: Commons.Border.none()
      radius: root.floating ? Commons.Style.cornerRadius : 0
      padding: root.cardPadding
      topPadding: root.edge === "top" ? root.floorPadding : root.cardPadding
      bottomPadding: root.edge === "bottom" ? root.floorPadding : root.cardPadding
      z: 1

      HoverHandler {
        id: cardHover
        onHoveredChanged: root.syncVisibility()
      }

      readonly property real edgeOffset: root.dockVisible
        ? root.edgeGap
        : -(dockCard.height + root.edgeGap + 10)
      property real slideOffset: dockCard.edgeOffset
      Behavior on slideOffset { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

      x: (parent.width - width) / 2
      y: root.edge === "top" ? slideOffset : parent.height - height - slideOffset

      opacity: root.dockVisible ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 180 }
      }

      width: root.expandBackground ? dockWindow.width - root.sideGap * 2
        : row.implicitWidth + contentLeftInset + contentRightInset
      height: row.implicitHeight + contentTopInset + contentBottomInset
      onWidthChanged: root.updateDockOverlap()

      MouseArea {
        id: cardArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton
        onClicked: if (root.contextAppId !== "") root.closeContext()
        onReleased: {
          if (root.dragAppId !== "") root.finishDrag()
        }
      }

      Rectangle {
        visible: root.dockCursorItem !== null
        x: row.x + (root.dockCursorItem ? root.dockCursorItem.x : 0)
        y: row.y
        width: root.dockCursorItem ? root.dockCursorItem.width : 0
        height: row.height
        radius: Commons.Style.cornerRadius
        color: Commons.Color.menu.selectedBackground
      }

      Grid {
        id: row
        z: 1
        spacing: Commons.Style.space(root.itemSpacing)
        columns: Math.max(1, root.elementTotal)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: dockCard.contentTopInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dockCard.contentBottomInset

        DockIconButton {
          dock: root
          id: appsButton
          visible: root.showAppsButton
          homeCenter: root.slotHomeCenter(0, 0, 0)
          icon: "view-app-grid"
          tooltip: "Applications"
          onPressed: Quickshell.execDetached({ command: ["hyprshell", "rofi-launch.sh", "d"], environment: { ROFI_INPUT_SOURCE: "mouse" } })
          onMiddleClicked: { if (root.shell) root.shell.run([root.shell.terminal]) }
          onWheelScrolled: function(dir) { root.cycleWorkspace(dir) }
          onMenuRequested: function(cx) { root.openDockSettingsMenu(cx) }
        }

        DockSeparator { dock: root; visible: root.appsSeparatorCount > 0 }

        Repeater {
          id: pinnedRepeater
          model: ScriptModel { values: root.pinnedSection; objectProp: "appId"; comparisonMode: ObjectComparison.Identity }
          delegate: DockItem {
            required property var modelData
            required property int index
            dock: root
            card: dockCard
            appId: modelData.appId
            name: modelData.name
            icon: modelData.icon
            running: modelData.running
            windows: modelData.windows
            windowList: modelData.windowList
            homeCenter: root.pinnedHomeCenter(index)
            pinned: true
            onActivateRequested: function(appId) { root.activate(appId) }
            onNewWindowRequested: function(appId) { root.launchApp(appId, null) }
            onMenuRequested: function(appId, cx) { root.openContext(appId, cx) }
            onWheelScrolled: function(appId, direction) { root.cycleApp(appId, direction) }
            onDragStarted: function(appId) {
              dock.dragAppId = appId
              dock.dropBeforeId = ""
            }
            onDragMoved: function(appId, main, away) { dock.updateDragTarget(appId, main, away) }
            onDragDropped: function(appId) { dock.finishDrag() }
          }
        }

        DockSeparator { dock: root; visible: root.hasLeftTileSeparator }

        Repeater {
          id: minimizedTilesRepeater
          model: root.tileModel

          delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property bool isGroup: modelData.type === "group"
            readonly property var win: isGroup ? modelData.windows[0] : modelData.win
            readonly property var groupWins: isGroup ? modelData.windows : [modelData.win]
            readonly property int groupCount: isGroup ? modelData.windows.length : 1
            readonly property string tileTitle: {
              if (isGroup) return groupCount + " windows — " + (modelData.title || "")
              return (win && win.title !== undefined) ? String(win.title) : ""
            }
            readonly property bool tileHovered: tileArea.containsMouse
            readonly property bool tileMenuOpen: root.contextAppId === "__tile_context__"

            readonly property real homeCenter: root.tileHomeCenter(index)
            property real magnifyScale: {
              if (root.waveHover) return root.magnifyScaleAt(tile.homeCenter)
              if (root.hoverEffect === "off") return 1
              return (tileArea.containsMouse && !tile.tileMenuOpen) ? root.zoomPeak : 1
            }
            Behavior on magnifyScale {
              NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
            }

            function doRestore() {
              root.restoreWindowBatch(groupWins)
            }

            function trigger(menu) {
              if (!tile.win || !tile.win.address) return
              if (menu) root.openTileContext(tile.groupWins, tile.win.appId || "", root.slotCenterX(tile))
              else tile.doRestore()
            }

            readonly property real tileMain: root.tileMainSize * (root.waveHover ? tile.magnifyScale : 1)
            width: tile.tileMain
            height: root.iconSlot
            opacity: root.dockVisible ? 1 : 0

            Item {
              id: tileVisual
              anchors.centerIn: parent
              width: tile.tileMain
              height: root.tileCrossSize
              scale: root.waveHover ? 1 : tile.magnifyScale

              Rectangle {
                visible: tile.isGroup && tile.groupCount > 1
                anchors.fill: parent
                anchors.leftMargin: -Commons.Style.space(3)
                anchors.bottomMargin: -Commons.Style.space(2)
                radius: root.tileRadius
                color: Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.16)
                border.width: 1
                border.color: Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.38)
              }
              Rectangle {
                visible: tile.isGroup && tile.groupCount > 2
                anchors.fill: parent
                anchors.leftMargin: -Commons.Style.space(6)
                anchors.bottomMargin: -Commons.Style.space(4)
                radius: root.tileRadius
                color: Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.11)
                border.width: 1
                border.color: Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.28)
              }

              Rectangle {
                anchors.fill: parent
                radius: root.tileRadius
                color: tileArea.containsMouse ? Commons.Color.menu.selectedBackground : Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.10)
                border.width: 1
                border.color: Commons.Util.scaleAlpha(Commons.Color.bar.text, 0.22)
              }

              Item {
                id: previewClip
                anchors.fill: parent
                anchors.margins: 1
                visible: tilePreview.hasContent
                clip: true
                layer.enabled: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: previewMask
                }

              ScreencopyView {
                id: tilePreview
                readonly property real boxWidth: previewClip.width
                readonly property real boxHeight: previewClip.height
                readonly property real srcAspect: sourceSize.height > 0
                  ? sourceSize.width / sourceSize.height
                  : boxWidth / Math.max(1, boxHeight)
                anchors.centerIn: parent
                width: Math.max(boxWidth, boxHeight * srcAspect)
                height: Math.max(boxHeight, boxWidth / srcAspect)
                live: false
                captureSource: tile.win && tile.win.waylandToplevel ? tile.win.waylandToplevel : null

                onCaptureSourceChanged: {
                  captureRetry.attempts = 0
                  captureRetry.restart()
                }
                onStopped: {
                  var src = captureSource
                  captureSource = null
                  Qt.callLater(function() { captureSource = src })
                }

                Timer {
                  id: captureRetry
                  interval: 140
                  property int attempts: 0
                  readonly property int maxAttempts: 6
                  repeat: attempts < maxAttempts
                  onTriggered: {
                    attempts++
                    if (!tilePreview.hasContent && tilePreview.captureSource) tilePreview.captureFrame()
                  }
                }
              }

              }

              Item {
                id: previewMask
                anchors.fill: previewClip
                visible: false
                layer.enabled: true
                Rectangle {
                  anchors.fill: parent
                  radius: root.tileRadius
                  color: "black"
                }
              }

              Rectangle {
                visible: (!tilePreview.hasContent || tile.groupCount > 1) && tile.win && tile.win.appId !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: Commons.Style.space(tile.groupCount > 1 ? 18 : 14)
                height: Commons.Style.space(tile.groupCount > 1 ? 18 : 14)
                radius: Commons.Style.space(3)
                color: Commons.Util.scaleAlpha(Commons.Color.bar.background, 0.85)

                Text {
                  anchors.centerIn: parent
                  text: {
                    if (!tile.win || !tile.win.appId) return "?"
                    return tile.groupCount > 1 ? String(tile.groupCount) : tile.win.appId.substring(0, 1).toUpperCase()
                  }
                  textFormat: Text.PlainText
                  color: Commons.Color.bar.text
                  font.family: Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                  font.bold: true
                }
              }
            }

            DockTooltip {
              dock: root
              target: tile
              gap: Commons.Style.space(6)
              visible: tile.tileHovered && !tile.tileMenuOpen && tile.tileTitle !== ""

              Text {
                text: {
                  if (!tile.isGroup) return tile.tileTitle
                  var lines = []
                  var max = Math.min(tile.groupWins.length, root.maxGroupTooltipLines)
                  for (var i = 0; i < max; i++) lines.push("• " + (tile.groupWins[i] ? tile.groupWins[i].title : ""))
                  if (tile.groupWins.length > root.maxGroupTooltipLines) lines.push("+" + (tile.groupWins.length - root.maxGroupTooltipLines) + " more")
                  return lines.join("\n")
                }
                textFormat: Text.PlainText
                color: Commons.Color.tooltip.text
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: tile.isGroup ? 8 : 1
              }
            }

            MouseArea {
              id: tileArea
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.slotEntered("__tile_context__", "")
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (mouse.button !== Qt.RightButton && root.contextAppId === "__tile_context__") root.closeContext()
                else tile.trigger(mouse.button === Qt.RightButton)
              }
            }
          }
        }

        DockSeparator { dock: root; visible: root.hasSeparator }

        Repeater {
          model: ScriptModel { values: root.runningSection; objectProp: "appId"; comparisonMode: ObjectComparison.Identity }
          delegate: DockItem {
            required property var modelData
            required property int index
            dock: root
            card: dockCard
            id: runningDockItem
            appId: modelData.appId
            name: modelData.name
            icon: modelData.icon
            running: modelData.running
            windows: modelData.windows
            windowList: modelData.windowList
            homeCenter: root.runningHomeCenter(index)
            pinned: false
            onActivateRequested: function(appId) { root.activate(appId) }
            onNewWindowRequested: function(appId) { root.launchApp(appId, null) }
            onMenuRequested: function(appId, cx) { root.openContext(appId, cx) }
            onWheelScrolled: function(appId, direction) { root.cycleApp(appId, direction) }
            onDragStarted: function(appId) { dock.dragAppId = appId }
            onDragMoved: function(appId, main, away) { dock.updateDragTarget(appId, main, away) }
            onDragDropped: function(appId) { dock.finishDrag() }

            readonly property bool isFullyTiled: root.showMinimizedTiles
              && DockModel.allWindowsMinimized(modelData.windowList, root.liveWsNameOf)
            visible: !isFullyTiled

            Binding {
              target: runningDockItem
              property: "width"
              when: runningDockItem.isFullyTiled
              value: 0
            }
          }
        }

        DockSeparator { dock: root; visible: root.hasFolderSeparator }

        Repeater {
          id: foldersRepeater
          model: root.pinnedFolders
          delegate: DockFolderItem {
            required property var modelData
            required property int index
            dock: root
            folderPath: modelData.path
            name: modelData.name || "Folder"
            icon: modelData.icon || DockModel.folderIconFor(modelData.path, "")
            homeCenter: root.folderHomeCenter(index)
            onOpenStackRequested: function(fpath, fname, cx) { root.openFolderStack(fpath, fname, cx) }
            onMenuRequested: function(fpath, fname, cx) { root.openFolderContext(fpath, fname, cx) }
          }
        }

        DockFolderItem {
          dock: root
          folderPath: "trash:///"
          name: "Trash"
          tooltip: "Trash"
          menuOwner: "__trash_context__"
          icon: root.trashFull ? "user-trash-full" : "user-trash"
          homeCenter: root.folderHomeCenter(root.pinnedFolders.length)
          onOpenStackRequested: root.openTrash()
          onMenuRequested: function(fpath, fname, cx) { root.openTrashContext(cx) }
        }
      }

      Rectangle {
        visible: root.dragAppId !== "" && root.dropIntoPins
        x: root.dropIndicatorMain
        y: row.y + (row.height - height) / 2
        width: Commons.Style.space(2)
        height: root.iconSize + Commons.Style.space(4)
        radius: 1
        color: Commons.Color.bar.active
        z: 10
      }
    }
  }

  DockPopup {
    dock: root
    host: dockWindow
    body: folderStack
    open: root.activeStackFolder !== "" && root.dockVisible
    anchorX: root.activeStackAnchor

    Loader {
      id: folderStack
      readonly property bool hovered: (folderStack.item as FolderStack)?.hovered === true
      active: root.activeStackFolder !== ""
      sourceComponent: FolderStack { dock: root }
    }
  }

  DockPopup {
    dock: root
    host: dockWindow
    body: contextMenu
    open: root.contextAppId !== ""
    anchorX: root.contextAnchor

    DockContextMenu {
      id: contextMenu
      dock: root
    }
  }
}

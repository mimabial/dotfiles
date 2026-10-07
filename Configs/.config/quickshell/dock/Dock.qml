pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._Screencopy
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import ".." as Shell
import "DockModel.js" as DockModel

Item {
  id: root

  component ContextRow: DockMenuRow { menuWidth: folderStackPopover.rowWidth }
  component MenuDivider: DockMenuDivider { menuWidth: folderStackPopover.rowWidth }

  required property var shell
  readonly property bool dockActive: !["windows", "niri"].includes(root.shell.workflow)
  property alias contextSelectedWindowIdx: contextMenu.selectedWindowIdx
  property alias dockCardItem: dockCard

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/quickshell/dock/pins.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/dock/settings.json"


  property bool blurred: true

  function setBlur(value) {
    root.blurred = value
    root.saveConfig()
  }
  function setDockEdge(value) {
    root.dockEdge = value
    root.saveConfig()
  }

  // Each bar layout pins the bar to one screen edge; while it shows, the dock
  // takes the opposite one so the two never share a side.
  readonly property string barEdge: root.shell ? String(root.shell.barEdge) : "top"
  readonly property bool barShown: root.shell ? root.shell.barShown === true || (root.shell.mode === "winbar" && root.shell.prefs.winbarAutoHide) : false
  property string dockEdge: "bottom"
  readonly property string edge: root.barShown
    ? (root.barEdge === "top" ? "bottom" : "top")
    : root.dockEdge
  // Main axis is the one icons march along; cross axis is the card's thickness.
  // The dock's "floor" is the side facing its screen edge: icons stand on it,
  // indicators line it, and a launch bounce lifts away from it. awaySign turns
  // the bounce's own negative magnitude into that outward direction.
  readonly property int awaySign: root.edge === "bottom" ? 1 : -1
  readonly property int floorTransformOrigin: root.edge === "bottom" ? Item.Bottom : Item.Top

  readonly property real panelGap: Style.space(6)
  function panelX(width, at) {
    return Math.max(Style.gapsOut, Math.min(dockWindow.width - width - Style.gapsOut, at - width / 2))
  }
  function panelY(height) {
    return root.edge === "top" ? dockCard.y + dockCard.height + root.panelGap : dockCard.y - height - root.panelGap
  }
  function parkedSince(address) { return root.parkedAt[address] !== undefined ? root.parkedAt[address] : 0 }
  readonly property int maxGroupTooltipLines: 6
  function tipY(hostHeight, tipHeight, gap) {
    gap = gap || Style.space(8)
    return root.edge === "top" ? hostHeight + gap : -tipHeight - gap
  }

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

  // Pushing the pointer against the dock's edge of another display brings the
  // dock there, as on macOS.
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


  // Raised cosine falloff, the curve Juan Pablo Zamora derived for this effect:
  //   size = min + ((1 - cos t) / 2) * (max - min)
  // over an effectWidth-wide window centred on the cursor, which is
  // 0.5 * (1 + cos(pi * d / R)) for a distance d and half-range R. Flat at the
  // peak and flat where the effect ends, so icons neither snap at the apex nor
  // pop into motion at the edge of the range.
  //
  // Slots grow, and the row grows with them. That is not a stylistic choice:
  // the displacement an icon needs is the accumulated growth between it and the
  // cursor, which integrates to (peak - 1) * R / 2 at the range edge — around
  // 30px per side here. A fixed-width card has nowhere to put that, so nudging
  // icons by a hand-picked amount instead leaves holes next to the pointer and
  // crowding further out. Letting the row carry the extra width is what keeps
  // every gap even.
  //
  // Distances are measured from each slot's *unmagnified* home centre, in
  // window coordinates. Nothing that magnification changes feeds back into
  // those numbers, so the wave cannot chase itself.
  readonly property var magnificationPresets: [{ name: "Subtle", scale: 0.6 }, { name: "Medium", scale: 1 }, { name: "Large", scale: 1.6 }]
  property real magnification: 1
  readonly property real magnifyPeak: 1 + 0.4 * root.magnification
  readonly property real zoomPeak: 1 + 0.22 * root.magnification
  readonly property real magnifyRange: root.iconSlot * 2.2

  // The card's own handler, lifted into window coordinates. Both terms move
  // together as the card grows, so their sum stays the physical pointer.
  readonly property real pointerMain: cardHover.hovered ? dockCard.x + cardHover.point.position.x : -1e6

  readonly property int appsSlots: root.showAppsButton ? 1 : 0
  // Running apps that actually render an icon. Fully-minimized unpinned apps
  // collapse to zero width (the tile section represents them), so they must
  // not keep dividers alive. When tiles are disabled the icons always show.
  readonly property int visibleRunningCount: {
    var n = 0
    for (var i = 0; i < root.runningSection.length; i++) {
      var item = root.runningSection[i]
      // Live resolver: the cached isMinimized flag can be stale right after a
      // park (Hyprland handle lag), which would keep a dead divider alive.
      if (root.showMinimizedTiles && item && DockModel.allWindowsMinimized(item.windowList, root.liveWsNameOf, root.isMinimizedWorkspace)) continue
      n++
    }
    return n
  }
  // Slot index of running entry idx among VISIBLE icons only. Fully-tiled
  // entries collapse to zero width, so they must not consume a slot in the
  // wave home-center arithmetic — every icon after one would drift by a
  // full slot. Same predicate as visibleRunningCount, so they never disagree.
  function visibleRunningSlotBefore(idx) {
    var n = 0
    for (var i = 0; i < idx && i < root.runningSection.length; i++) {
      var e = root.runningSection[i]
      if (!(root.showMinimizedTiles && e && DockModel.allWindowsMinimized(e.windowList, root.liveWsNameOf, root.isMinimizedWorkspace))) n++
    }
    return n
  }
  // Pinned-group | running divider. Sits after the tile section when tiles
  // exist, so it doubles as the right tile divider.
  readonly property int groupSlots: root.appGroups.length
  readonly property bool hasSeparator: (root.pinnedSection.length > 0 || root.groupSlots > 0 || root.hasTiles)
    && root.visibleRunningCount > 0
  // itemSpacing is in 32nds of an icon, so the gap keeps its proportion at any size.
  readonly property real gapWidth: Math.round(root.iconSize * root.itemSpacing / 32)
  readonly property real separatorWidth: Style.space(1)
  readonly property int folderSlots: root.pinnedFolders.length + 1
  readonly property bool hasFolderSeparator: root.folderSlots > 0
    && (root.pinnedSection.length > 0 || root.groupSlots > 0 || root.hasTiles || root.visibleRunningCount > 0)

  readonly property var tileModel: {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      return list.map(function (win) { return { type: "single", win: win } })
    }
    var groups = {}
    var order = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var key = w.appId || w.address
      if (!groups[key]) {
        groups[key] = { type: "group", appId: key, title: w.title, windows: [] }
        order.push(key)
      }
      groups[key].windows.push(w)
    }
    // Oldest member parks the group's slot in line.
    order.sort(function (a, b) { return root.parkedSince(groups[a].windows[0].address) - root.parkedSince(groups[b].windows[0].address) })
    return order.map(function (key) { return groups[key] })
  }
  readonly property int tileCount: root.tileModel.length
  readonly property real tileCrossSize: Math.round(root.iconSlot * 0.95)
  readonly property real tileMainSize: Math.round(root.iconSlot * 1.5)

  readonly property real tileRadius: Math.min(Style.cornerRadius, root.tileCrossSize / 2)
  readonly property bool hasTiles: root.tileCount > 0
  readonly property bool hasLeftTileSeparator: root.hasTiles && (root.pinnedSection.length > 0 || root.groupSlots > 0)

  // Width arithmetic total: hidden (fully-tiled) entries occupy zero width,
  // so the row-width and gap math must count only visible icons.
  readonly property int visibleSlotTotal: root.appsSlots + root.pinnedSection.length + root.groupSlots
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

  // Where the row would start if nothing were magnified, measured along the
  // main axis. The card is centred, so this only moves when its contents change.
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
  function groupHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length + index
    return root.slotHomeCenter(iconsBefore + root.appsSeparatorCount, iconsBefore, root.appsSeparatorCount)
  }
  function tileHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length + root.groupSlots + index
    var leftSeparator = root.hasLeftTileSeparator ? 1 : 0
    var tileWidthOffset = leftSeparator * root.separatorWidth + index * root.tileMainSize
      + (root.tileMainSize - root.iconSlot) / 2
    return root.slotHomeCenter(iconsBefore + root.appsSeparatorCount + leftSeparator,
      iconsBefore, root.appsSeparatorCount, tileWidthOffset)
  }
  function runningHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length + root.groupSlots
      + root.visibleRunningSlotBefore(index)
    var separators = root.appsSeparatorCount + (root.hasSeparator ? 1 : 0)
    return root.slotHomeCenter(iconsBefore + separators + (root.hasLeftTileSeparator ? 1 : 0) + root.tileElements,
      iconsBefore, separators, root.tilesFixedWidth)
  }
  function folderHomeCenter(index) {
    var iconsBefore = root.appsSlots + root.pinnedSection.length + root.groupSlots
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
    : Math.max(28, Math.round(Style.bar.sizeHorizontal * 0.9))
  // Proportions follow the icon, as on macOS: a slot is the icon itself and the
  // card's padding is a fraction of it. The running dots sit in the floor-side
  // padding, which grows to hold them.
  readonly property int iconSlot: root.iconSize
  readonly property int cardPadding: Math.round(root.iconSize / 8)
  readonly property real indicatorHeight: Style.space(5)
  readonly property real floorPadding: root.cardPadding + (root.showIndicators ? root.indicatorHeight : 0)
  function indicatorY(hostHeight, height) {
    return root.edge === "top" ? -height - root.cardPadding / 2 : hostHeight + root.cardPadding / 2
  }


  property var pinnedIds: []
  property var appRows: []
  property var dockModel: ({ pinned: [], running: [] })
  // Live scan of parked windows for the preview-tile section. Built straight
  // off Hyprland's own toplevel list, so it cannot go stale the way cached
  // model primitives can.
  property var minimizedWindows: []
  property string _minimizedSig: ""
  readonly property var pinnedSection: root.dockModel.pinned || []
  readonly property var runningSection: root.dockModel.running || []
  readonly property var groupedSection: root.dockModel.grouped || []

  // macOS keeps the last few unpinned apps in the dock after they quit.
  readonly property int recentLimit: root.showRecents ? 3 : 0
  property var recentIds: []
  readonly property bool contextIsRecent: root.recentIds.indexOf(root.contextAppId) >= 0

  function buildDockModel(recents) {
    return DockModel.buildEntries(root.pinnedIds,
                                  (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []),
                                  root.appRows, root.appLibrary, root.hyprToplevelFor,
                                  root.isMinimizedWorkspace, root.minimizedOrigins, root.appGroups,
                                  recents, root.recentLimit)
  }

  function refreshDock() {
    var model = root.buildDockModel(root.recentIds)
    var stillRunning = model.running.filter(e => e.running).map(e => e.appId)
    var quit = root.runningSection.filter(e => e.running && stillRunning.indexOf(e.appId) < 0
      && DockModel.entryFor(root.appRows, e.appId)).map(e => e.appId)
    if (quit.length > 0) model = root.buildDockModel(quit.concat(root.recentIds))
    var recents = model.running.filter(e => !e.running).map(e => e.appId)
    if (String(recents) !== String(root.recentIds)) {
      root.recentIds = recents
      root.saveConfig()
    }
    root.dockModel = model
    root.rescanMinimizedWindows()
    root.pruneLaunching()
    root.pruneWindowState()
  }

  function rescanMinimizedWindows() {
    var mins = []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tops.length; i++) {
      var h = tops[i]
      if (!h) continue
      var addr = root.windowAddress(h)
      if (!addr) continue
      var isParked = (h.workspace && root.isMinimizedWorkspace(h.workspace.name))
                  || (root.minimizedOrigins && root.minimizedOrigins[addr] !== undefined)
      if (!isParked) continue
      var top = root.liveToplevelForAddress(addr)
      var title = String((top && top.title) || h.title || "Window")
      var appId = ""
      try {
        appId = h.appId ? DockModel.normalizeId(h.appId)
          : (top && top.appId ? DockModel.normalizeId(top.appId) : "")
      } catch (e) {}
      mins.push({ address: addr, title: title, appId: appId, waylandToplevel: top })
    }
    // Oldest parked first, so the tiles read chronologically left to right.
    mins.sort(function (a, b) { return root.parkedSince(a.address) - root.parkedSince(b.address) })
    // Assign only on real change: a fresh array per rebuild would recreate
    // every tile delegate on unrelated events, eating clicks and forcing
    // pointless capture re-negotiations.
    var sig = mins.map(function (win) { return win.address }).join(",")
    if (sig !== root._minimizedSig) {
      root._minimizedSig = sig
      root.minimizedWindows = mins
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
  onActiveIdChanged: if (root.activeId) root.clearUrgentApp(root.activeId, root.activeWindowAddress)
  onActiveWindowAddressChanged: if (root.activeWindowAddress) root.clearUrgentApp(root.activeId, root.activeWindowAddress)

  readonly property string dockMonitorName: dockScreen ? String(dockScreen.name || "") : ""
  property string dockSpecialWorkspace: ""
  property bool dockSpecialSeeded: false

  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace
    ? Hyprland.focusedWorkspace.id
    : -99999

  readonly property string focusedWorkspaceName: Hyprland.focusedWorkspace
    ? String(Hyprland.focusedWorkspace.name || Hyprland.focusedWorkspace.id || "")
    : ""

  // Hyprland has no minimize, so a window is parked on its own hidden special
  // workspace. The workspace name is the state, which means it survives a shell
  // restart; only the origin workspace is remembered here, and losing it just
  // means the window comes back to wherever you are.
  // Each parked window gets its own special workspace. Sharing one means
  // Hyprland tiles the parked windows against each other, and since the preview
  // is captured after the move, every thumbnail took the shape of a window
  // sharing a workspace rather than the shape it actually had.
  readonly property string minimizedWorkspacePrefix: "special:minimized"

  function minimizedWorkspaceFor(address) {
    var addr = String(address || "").replace(/^0x/i, "")
    return addr ? root.minimizedWorkspacePrefix + "-" + addr : root.minimizedWorkspacePrefix
  }

  // A scratchpad window belongs to its own special workspace. Restoring one
  // "here" strands it on a normal workspace, where the keybind that summons it
  // no longer finds it — so for these the origin always wins over the current
  // workspace, whatever the caller asked for.
  function isScratchpadWorkspace(name) {
    var value = String(name || "")
    return value.indexOf("special:") === 0 && !root.isMinimizedWorkspace(value)
  }

  // The bare prefix still counts, so windows parked under the old shared scheme
  // are recognised and can be restored.
  function isMinimizedWorkspace(name) {
    var value = String(name || "")
    return value === root.minimizedWorkspacePrefix
      || value.indexOf(root.minimizedWorkspacePrefix + "-") === 0
  }
  property var minimizedOrigins: ({})
  property var parkedAt: ({})
  property var urgentMap: ({})
  property var recentOpenedWindowAddrs: ({})

  // Per app: the window it parked last, and the window it was in last. Both
  // hold addresses rather than live handles — a closed window then leaves a
  // stale string that the next prune drops, instead of a dangling object.
  // Hyprland's own focusHistoryID would save the bookkeeping, but Quickshell
  // only refreshes lastIpcObject on window open/close, so it goes stale the
  // moment focus moves.
  property var appRecentWindow: ({})

  property var launchPending: ({})
  readonly property int launchTimeout: 12000


  property string dragAppId: ""
  property bool dragRemove: false
  property string dropBeforeId: ""
  property string dropTargetAppId: ""
  property string dropTargetGroupId: ""
  property string dragSourceGroupId: ""
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
  property var activeStackEntries: []
  property int activeStackTotalCount: 0
  property real activeStackAnchor: 0
  property string contextFolderPath: ""
  property string contextFolderName: ""

  property var appGroups: []
  property string activeAppGroupId: ""
  property var activeAppGroupData: null
  property real activeAppGroupAnchor: 0
  property var contextAppGroupData: null
  property bool appGroupEditing: false
  property bool appGroupFocusPriming: false
  property bool menuFocusPriming: false
  property int menuCursor: -1
  property var menuRows: []

  function clearMenuCursor() {
    for (var row of menuRows) if (row) row.cursored = false
    menuRows = []
    menuCursor = -1
  }
  function collectMenuRows(item, rows) {
    for (var child of item.children) {
      if (!child.visible) continue
      if (child.navigable === true) rows.push(child)
      collectMenuRows(child, rows)
    }
  }
  function moveMenuCursor(step) {
    var panel = contextAppId !== "" ? contextMenu : activeStackFolder !== "" ? folderStackPopover : appGroupPopup
    var rows = []
    collectMenuRows(panel, rows)
    menuRows = rows
    if (!rows.length) return
    menuCursor = menuCursor < 0 ? (step > 0 ? 0 : rows.length - 1)
      : (menuCursor + step + rows.length) % rows.length
    for (var i = 0; i < rows.length; i++) rows[i].cursored = i === menuCursor
  }
  function handleMenuKey(event) {
    if (appGroupEditing) return false
    if (!anyPanelOpen) return dockCursor >= 0 && handleDockKey(event)
    if (event.key === Qt.Key_F2 && activeAppGroupId !== "") { appGroupPopup.beginRename(); return true }
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left) {
      if (contextAppId === "__dock_settings__" && settingsSubmenu !== "") settingsSubmenu = ""
      else if (contextAppId !== "") closeContext()
      else if (activeStackFolder !== "") closeFolderStack()
      else closeAppGroup()
      clearMenuCursor()
      return true
    }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { moveMenuCursor(1); return true }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { moveMenuCursor(-1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space || event.key === Qt.Key_Right) {
      if (menuCursor < 0) moveMenuCursor(1)
      var row = menuRows[menuCursor]
      if (row) {
        if (row.activateKeyboard) row.activateKeyboard()
        else row.triggered()
      }
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

  // The cursor is a slot index, so it survives the row rebuilding its items.
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
  // "zoom" grows only the icon under the pointer and leaves the layout alone —
  // the behaviour this dock shipped with, and the default. "wave" is the
  // falloff: neighbours respond and the row carries the extra width. "off" is
  // no hover growth at all.
  property string hoverEffect: "zoom"
  readonly property int popoverZ: 100
  readonly property int tooltipZ: 300
  readonly property bool waveHover: root.hoverEffect === "wave"
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0
  // Every surface the dock draws — card, menus, popover, tooltips — sits at the
  // same opacity, so the menus do not read as a denser material than the dock
  // they belong to. PopupCard's 0.92 is right for a free-standing popup over
  // arbitrary content; a dock menu is part of the dock.

  // "Auto (Theme)" matches the bar. The palette colours are opaque and the bar
  // applies its opacity itself, so the alpha comes from the bar rather than
  // from Color.bar.background.
  readonly property real effectiveDockOpacity: Math.min(1, root.dockOpacity >= 0 ? root.dockOpacity : Style.barOpacity)
  property int themeVersion: 0
  property string folderColor: "theme"
  readonly property bool symbolicFolders: ["white", "black", "symbolic"].indexOf(root.folderColor) >= 0
  readonly property color symbolicFolderColor: root.folderColor === "white" ? "#ffffff"
    : root.folderColor === "black" ? "#111111" : Color.bar.text
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

  Timer {
    id: hideTimer
    interval: 350
    onTriggered: root.dockVisible = false
  }

  Timer {
    id: appGroupFocusTimer
    interval: Style.focusPrimeDelay
    onTriggered: root.appGroupFocusPriming = false
  }
  Timer {
    id: menuFocusTimer
    interval: Style.focusPrimeDelay
    onTriggered: root.menuFocusPriming = false
  }

  // Dwell on the screen edge before revealing, so a pointer travelling to the
  // bottom of a window does not summon the dock on its way past.
  Timer {
    id: revealTimer
    interval: root.revealDelay
    onTriggered: root.dockVisible = true
  }

  // Coalesces model rebuilds: several signals can describe one window change.
  Timer {
    id: modelTimer
    interval: 40
    onTriggered: root.refreshDock()
  }

  // One-shot deferred rebuild after park/restore moves and configreloaded events,
  // so model state is re-frozen once Hyprland handles settle.
  Timer {
    id: modelSettleTimer
    interval: 300
    onTriggered: root.refreshDock()
  }

  Timer {
    id: launchPruneTimer
    interval: 500
    repeat: true
    onTriggered: root.pruneLaunching()
  }

  Timer {
    id: debounceOverlapTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (root.autohide && root.intelligentAutohide) {
        root.checkDockOverlap()
      }
    }
  }

  // Periodic fallback overlap check — deliberate exception to the zero-CPU-polling invariant.
  // Hyprland does not emit IPC events for in-progress window drags, so there is no event-driven
  // way to detect a window being dragged over the dock. It is fully gated: stops when hidden,
  // when the user hovers the dock card, and during menus / drag reorder — so CPU cost is zero at
  // rest. A sample lands one tick after it is asked for, so the interval is half the detection
  // latency it buys, and each tick is a socket round trip rather than a process.
  Timer {
    id: intelligentOverlapCheckTimer
    interval: 175
    repeat: true
    running: root.autohide && root.intelligentAutohide && root.dockVisible && !(cardHover && cardHover.hovered) && !(revealHover && revealHover.hovered) && root.contextAppId === "" && root.dragAppId === ""
    onTriggered: root.checkDockOverlap()
  }

  // Quickshell only refreshes lastIpcObject on window open/close and the refresh
  // answers asynchronously, so each pass reads the sample the previous pass asked
  // for and requests the next. Costs a socket round trip, not a hyprctl fork.
  function checkDockOverlap() {
    Hyprland.refreshToplevels()
    var clients = []
    var tops = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
    for (const toplevel of tops) {
      var ipc = toplevel ? toplevel.lastIpcObject : null
      if (ipc) clients.push(ipc)
    }

    // Resolve the monitor this dock actually lives on — the globally
    // focused monitor is the wrong coordinate frame on multi-monitor
    // setups whenever focus sits on another output.
    var mon = null
    var dockName = dockScreen ? String(dockScreen.name || "") : ""
    if (dockName !== "" && Hyprland.monitors) {
      var monitors = Hyprland.monitors.values || []
      for (var m = 0; m < monitors.length; m++) {
        if (monitors[m] && String(monitors[m].name || "") === dockName) {
          mon = monitors[m]
          break
        }
      }
    }
    if (!mon) mon = Hyprland.focusedMonitor
    if (!mon || !(mon.width > 0 && mon.scale > 0) || dockCard.width <= 0) return

    var overlapMargin = 12
    var screenLogicalW = mon.width / mon.scale
    var screenLogicalH = mon.height / mon.scale
    var footprintWidth = dockCard.width + Style.gapsOut * 2
    var footprintDepth = dockCard.height + Style.gapsOut * 2 + overlapMargin
    var footprintLeft = mon.x + (screenLogicalW - footprintWidth) / 2
    var footprintRight = mon.x + (screenLogicalW + footprintWidth) / 2
    var footprintTop = root.edge === "top" ? mon.y : mon.y + screenLogicalH - footprintDepth
    var footprintBottom = root.edge === "top" ? mon.y + footprintDepth : mon.y + screenLogicalH

    var overlap = false
    // Compare against the dock monitor's own active workspace, not the
    // global focus — windows visible next to the dock on its output are
    // the ones that can overlap it.
    var dockWsId = (mon && mon.activeWorkspace) ? mon.activeWorkspace.id : -1

    // A scratchpad is not the active workspace — Hyprland keeps it in a slot of
    // its own — so its windows have to be admitted separately or a full-screen
    // one reads as an empty desktop. The name is maintained by the activespecial
    // event; the monitor object is only correct on the first read, so it seeds.
    if (!root.dockSpecialSeeded && mon && mon.lastIpcObject && mon.lastIpcObject.specialWorkspace) {
      root.dockSpecialWorkspace = String(mon.lastIpcObject.specialWorkspace.name || "")
      root.dockSpecialSeeded = true
    }
    var dockSpecialWs = root.dockSpecialWorkspace

    for (var i = 0; i < clients.length; i++) {
      var client = clients[i]
      if (!client.mapped || client.hidden) continue
      if (!client.workspace) continue
      if (client.workspace.id !== dockWsId
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

  // Unread counts apps publish over the Unity LauncherEntry D-Bus API. Apps only
  // announce changes, so a count set before the shell started shows at the next one.
  property var badgeCounts: ({})
  function badgeCountFor(appId) {
    for (var id in root.badgeCounts)
      if (DockModel.isAppMatch(id, appId)) return root.badgeCounts[id]
    return 0
  }
  Process {
    running: true
    command: ["python3", Quickshell.env("HOME") + "/.local/lib/hypr/quickshell/launcher-entry.py"]
    stdout: SplitParser {
      onRead: function(line) {
        var update = JSON.parse(line)
        var next = DockModel.copyMap(root.badgeCounts)
        if (update.count > 0) next[update.app] = update.count
        else delete next[update.app]
        root.badgeCounts = next
      }
    }
  }

  Process {
    id: folderStackScanner
    property string targetFolder: ""
    command: ["python3", Quickshell.env("HOME") + "/.local/lib/hypr/quickshell/dock-folders.py", "scan", folderStackScanner.targetFolder]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(this.text) || { count: 0, items: [] }
          // Stale-result guard: only apply if this scan is still for the
          // folder the user currently has open (or any at all). Prevents a
          // slow older scan from painting one folder's files under another's
          // header, or repopulating after the stack was closed.
          var wanted = String(root.activeStackFolder || "").replace(/^~/, Quickshell.env("HOME"))
          if (parsed.folder !== wanted) return
          root.activeStackTotalCount = parsed.count || 0
          root.activeStackEntries = parsed.items || []
        } catch (e) {
          root.activeStackTotalCount = 0
          root.activeStackEntries = []
        }
      }
    }
  }

  function pickCustomFolder() { if (!customFolderPickerProc.running) customFolderPickerProc.running = true }

  Process {
    id: customFolderPickerProc
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

  // A menu or popover follows the pointer off the dock. The grace period covers
  // the gap between the slot and the panel, which neither handler reports as
  // hovered while the cursor crosses it.
  readonly property bool pointerOverDock: (cardHover && cardHover.hovered)
    || contextMenu.hovered
    || (stackHover && stackHover.hovered)
    || appGroupPopup.hovered
  readonly property bool anyPanelOpen: root.contextAppId !== "" || root.activeStackFolder !== ""
    || root.activeAppGroupId !== ""

  onPointerOverDockChanged: root.syncPanelDismiss()
  onAnyPanelOpenChanged: root.syncPanelDismiss()

  // A menu or popover is anchored to the slot that opened it, so moving onto a
  // different slot strands it beside a neighbour it has nothing to do with.
  // Dragging is exempt: the pointer crosses every slot on its way.
  function slotEntered(menuOwner, stackOwner, groupOwner) {
    if (root.dragAppId !== "") return
    root.dockCursor = -1
    if (root.contextAppId !== "" && root.contextAppId !== menuOwner) root.closeContext()
    if (root.activeStackFolder !== "" && root.activeStackFolder !== stackOwner) root.closeFolderStack()
    if (root.activeAppGroupId !== "" && root.activeAppGroupId !== groupOwner) root.closeAppGroup()
  }

  function syncPanelDismiss() {
    if (root.pointerOverDock || !root.anyPanelOpen || root.dragAppId !== "" || root.dockCursor >= 0) panelLeaveTimer.stop()
    else panelLeaveTimer.restart()
  }

  Timer {
    id: panelLeaveTimer
    interval: 350
    onTriggered: {
      if (root.pointerOverDock || root.dragAppId !== "") return
      if (root.contextAppId !== "") root.closeContext()
      if (root.activeStackFolder !== "") root.closeFolderStack()
      if (root.activeAppGroupId !== "") root.closeAppGroup()
    }
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
      || root.activeAppGroupId !== "" || root.dockCursor >= 0

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
  onActiveAppGroupIdChanged: { root.syncVisibility(); root.primeMenuFocus() }
  onSettingsSubmenuChanged: root.clearMenuCursor()
  onAppGroupEditingChanged: {
    root.appGroupFocusPriming = root.appGroupEditing
    if (root.appGroupEditing) appGroupFocusTimer.restart()
    else appGroupFocusTimer.stop()
  }
  onDragAppIdChanged: root.syncVisibility()
  onDockActiveChanged: root.syncVisibility()
  onAutohideChanged: root.syncVisibility()
  onIntelligentAutohideChanged: {
    if (root.intelligentAutohide) debounceOverlapTimer.restart()
    root.syncVisibility()
  }
  onWindowsOverlapDockChanged: root.syncVisibility()
  onDockVisibleChanged: {
    if (!root.dockVisible) {
      root.closeContext()
      root.closeFolderStack()
      root.closeAppGroup()
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

  // The renderer rewrites this on every theme and wallpaper change, so it is the
  // signal that palette-derived colours need re-reading.
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

  // Chimes ask dunst whether it is paused instead of watching a DND file, so
  // nothing runs until a window actually raises urgency (zero-CPU idle holds).
  function playUrgentChime() {
    if (!root.urgentSound || root.urgentSoundName === "none") return
    if (!dndProbe.running) dndProbe.running = true
  }

  Process {
    id: dndProbe
    command: ["dunstctl", "is-paused"]
    stdout: StdioCollector {
      // Empty output means dunstctl is unavailable; that is not do-not-disturb.
      onStreamFinished: {
        if (String(this.text || "").trim() === "true") return
        Quickshell.execDetached(["canberra-gtk-play", "-i", root.urgentSoundName])
      }
    }
  }


  Connections {
    target: Color
    function onShellChanged() { root.handleThemeChanged() }
    function onForegroundChanged() { root.handleThemeChanged() }
    function onAccentChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: Style
    function onFontFamilyChanged() { root.handleThemeChanged() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rescanApps() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() {
      modelTimer.restart()
      debounceOverlapTimer.restart()
      root.syncContextWindows()
    }
  }

  // Hyprland resolves its own handle for a window slightly apart from the
  // Wayland announcement; rebuilding on both is what keeps the handles attached.
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      modelTimer.restart()
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      try {
        var top = ToplevelManager.activeToplevel
        if (top && top.appId) {
          var aid = DockModel.normalizeId(top.appId)
          var address = root.windowAddress(root.hyprToplevelFor(top))
          if (aid && address) {
            var recent = DockModel.copyMap(root.appRecentWindow)
            recent[aid] = address
            root.appRecentWindow = recent
          }
          root.clearUrgentApp(aid, address)
        } else if (top) {
          var addressOnly = root.windowAddress(root.hyprToplevelFor(top))
          if (addressOnly) root.clearUrgentApp("", addressOnly)
        }
      } catch (e) {}
      debounceOverlapTimer.restart()
      root.syncContextWindows()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      debounceOverlapTimer.restart()
    }
    function onRawEvent(event) {
      var n = String((event && event.name) || "")
      if (n === "activespecial") {
        var special = String(event.data || "").split(",")
        var onMonitor = special.length > 1 ? special[special.length - 1].trim() : ""
        if (onMonitor === "" || onMonitor === root.dockMonitorName) {
          root.dockSpecialWorkspace = special[0].trim()
          root.dockSpecialSeeded = true
          debounceOverlapTimer.restart()
        }
      }
      if (n === "openwindow") {
        var rawAddr = String(event.data || "").split(",")[0].trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr
        var rec = DockModel.copyMap(root.recentOpenedWindowAddrs)
        rec[fullAddr] = Date.now() + 3000
        root.recentOpenedWindowAddrs = rec
      }
      if (n === "urgent") {
        var rawAddr = String(event.data || "").trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr

        var activeAddr = root.windowAddress(root.hyprToplevelFor(ToplevelManager.activeToplevel))
        if (activeAddr && activeAddr === fullAddr) {
          return
        }

        if (root.recentOpenedWindowAddrs && root.recentOpenedWindowAddrs[fullAddr] && Date.now() < root.recentOpenedWindowAddrs[fullAddr]) {
          return
        }

        var allEntries = root.pinnedSection.concat(root.runningSection)
        for (var e = 0; e < allEntries.length; e++) {
          var entry = allEntries[e]
          if (!entry) continue
          if (root.launchPending && root.launchPending[entry.id]) {
            var wins = entry.windowList || []
            if (wins.some(function (win) { return win && win.address === fullAddr })) return
          }
        }

        var map = DockModel.copyMap(root.urgentMap)
        map[fullAddr] = true
        root.urgentMap = map
        modelTimer.restart()
        root.playUrgentChime()
      }
      if (n === "activewindow" || n === "activewindowv2") {
        var eventData = String(event.data || "").trim()
        if (n === "activewindowv2") {
          var rawAddr = eventData.split(",")[0].trim()
          if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
          var fullAddr = "0x" + rawAddr
          root.clearUrgentApp("", fullAddr)
        } else {
          var winClass = eventData.split(",")[0].trim()
          if (winClass) root.clearUrgentApp(winClass, "")
        }
      }
      if (n === "closewindow") {
        var rawAddr = String(event.data || "").trim()
        if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
        var fullAddr = "0x" + rawAddr
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
        root.refreshDock()
      }
      if (n === "workspace" || n === "workspacev2" || n === "openwindow" || n === "closewindow" ||
          n === "movewindow" || n === "movewindowv2" || n === "activewindow" || n === "activewindowv2" ||
          n === "changefloatingmode" || n === "fullscreen" || n === "pin" || n === "focusedmon") {
        debounceOverlapTimer.restart()
      }
      if (n === "openwindow" || n === "closewindow" || n === "urgent"
          || n === "movewindow" || n === "movewindowv2"
          || n === "workspace" || n === "workspacev2") modelTimer.restart()
      // Park/restore moves get one deferred rebuild: the 40ms rebuild can land
      // inside Quickshell's Hyprland-handle lag and freeze pre-move state into
      // the model (stale isMinimized kept the running icon beside its tile).
      // Event-driven single shot — self-terminating, no polling.
      if (n === "movewindow" || n === "movewindowv2") modelSettleTimer.restart()
      // configreloaded fires Quickshell refreshWorkspaces + refreshToplevels
      // which destroy/recreate workspace objects and re-assign toplevel handles.
      // Settle handles cleanly via modelSettleTimer.
      if (n === "configreloaded") modelSettleTimer.restart()
    }
  }

  onShellChanged: {
    Style.shell = root.shell
    Color.shell = root.shell
    root.rescanApps()
  }
  onPinnedIdsChanged: root.refreshDock()
  onShowRecentsChanged: root.refreshDock()
  onAppGroupsChanged: root.refreshDock()


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
    // Migrates the old boolean: an explicit magnification:false meant no growth.
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
    root.appGroups = parsed && Array.isArray(parsed.appGroups) ? parsed.appGroups : []
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
    root.refreshDock()
  }

  function handleThemeChanged() {
    root.themeVersion++
    root.rescanApps()
  }

  // Upstream also offered Yaru's coloured folder sets; those ship with Ubuntu's
  // icon theme, which is not installed here, so only the monochrome modes remain.
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
    // No handles to tell parked from visible: fall back to the pure order.
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

  // Hyprland 0.56 moved dispatchers to Lua; Quickshell reports which syntax
  // the running compositor speaks.
  function hyprDispatch(lua, legacy) {
    Hyprland.dispatch(Hyprland.usingLua ? lua : legacy)
  }

  // "e+1"/"e-1" are Hyprland workspace selectors: the nearest existing one, relative.
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
      for (var i = 0; i < tops.length; i++) {
        var top = tops[i]
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
      for (var i = 0; i < tops.length; i++) {
        var h = tops[i]
        if (h && root.windowAddress(h) === addr) return h
      }
    } catch (e) {}
    return null
  }

  function focusWindowByAddress(addr, appId) {
    if (!addr) return
    root.clearUrgentApp(appId || "", addr)
    var handle = root.liveHyprToplevelForAddress(addr)
    var top = root.liveToplevelForAddress(addr)


    if (handle) {
      var workspace = handle.workspace
      if (workspace && root.isMinimizedWorkspace(workspace.name)) {
        root.restoreWindow(addr, appId)
        return
      }
      if (top) DockModel.focusWindow(top)
      if (workspace && Hyprland.focusedWorkspace && workspace.id !== Hyprland.focusedWorkspace.id) {
        var targetWs = root.workspaceTarget(workspace)
        if (targetWs) {
          root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                            "workspace " + targetWs)
        }
      }
    } else if (top) {
      root.focusToplevel(top, appId)
    }
  }

  // Native Wayland activation hands over focus without warping the pointer away from
  // the dock or desynchronizing layer-shell input state.
  function focusToplevel(toplevel, appId) {
    if (!toplevel) return
    var handle = root.hyprToplevelFor(toplevel)
    var addr = root.windowAddress(handle)
    var aid = appId || (toplevel.appId ? DockModel.normalizeId(toplevel.appId) : "")
    root.clearUrgentApp(aid, addr)
    var workspace = handle ? handle.workspace : null

    if (workspace && root.isMinimizedWorkspace(workspace.name)) {
      root.restoreWindow(handle, aid)
      return
    }

    DockModel.focusWindow(toplevel)

    if (workspace && Hyprland.focusedWorkspace && workspace.id !== Hyprland.focusedWorkspace.id) {
      var targetWs = root.workspaceTarget(workspace)
      if (targetWs) {
        root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(targetWs) + '" })',
                          "workspace " + targetWs)
      }
    }
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
    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(parkWs) + '", follow = false })',
      "movetoworkspacesilent " + parkWs + ",address:" + address)

    // A shown scratchpad with nothing left on it would linger as an empty overlay.
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

    // Silent move (follow = false): a dispatcher-driven window focus would
    // warp the mouse pointer into the restored window's center. The workspace
    // switch plus native Wayland activation below focus the window cleanly
    // and leave the cursor exactly where the user left it.
    root.hyprDispatch(
      'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
        + root.luaString(target) + '", follow = false })',
      "movetoworkspacesilent " + target + ",address:" + address)
    // Switch only when the window returns elsewhere: re-focusing the shown
    // workspace does nothing, and the scrolling layout rejects it while empty.
    if (target !== here) root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                                           "workspace " + target)

    var top = root.liveToplevelForAddress(address)
    if (top) {
      DockModel.focusWindow(top)
    }
    return true
  }

  // One compositor transaction: every move goes out silently first, then the
  // workspace focus and window activation happen once. Calling restoreWindow() in a
  // loop flashed each window fullscreen in turn, since every call switched focus and
  // activated on its own.
  function restoreWindowBatch(wins, primaryAddress, useOrigin) {
    if (!wins || wins.length === 0) return

    // Single-copy the maps — O(n) instead of O(n²) individual copies.
    var origins = DockModel.copyMap(root.minimizedOrigins)
    var parkedTimes = DockModel.copyMap(root.parkedAt)

    var focusAddr = null
    var focusTarget = null
    var bestTime = -1
    var here = root.workspaceTarget(Hyprland.focusedWorkspace)

    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (!w || !w.address) continue
      var address = w.address

      var origin = origins[address] || ""
      var target = (useOrigin || root.isScratchpadWorkspace(origin)) && origin ? origin : here
      if (!target) continue

      var parkedTime = parkedTimes[address] !== undefined ? parkedTimes[address] : 0
      delete origins[address]
      delete parkedTimes[address]

      root.hyprDispatch(
        'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
          + root.luaString(target) + '", follow = false })',
        "movetoworkspacesilent " + target + ",address:" + address)

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
      var top = root.liveToplevelForAddress(focusAddr)
      if (top) DockModel.focusWindow(top)
    }
  }

  // The workspace a window sits on right now. Model primitives freeze state at
  // rebuild time, and Quickshell's Hyprland handle can lag silent moves onto
  // the special workspace, so park/visibility decisions resolve live at click
  // time and fall back to the cached name only while no handle exists.
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

  // Nothing is remembered for this: the workspace a window sits on is the answer,
  // so a shell restart cannot lose track of one.
  function parkedWindows(windows) {
    return DockModel.windowsByParkedState(windows, root.isWinParkedLive, true)
  }

  // Windows parked before this shell session have no timestamp and sort first,
  // matching the "recover the oldest" expectation.
  function oldestParked(parked) {
    return DockModel.oldestWindow(parked, root.parkedAt)
  }

  function recentWindow(appId, windows) {
    return root.windowByAddress(windows, root.appRecentWindow[appId])
  }

  function minimizeAllWindows(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var parked = false
    for (var i = 0; i < windows.length; i++) {
      var win = windows[i]
      if (!win || !win.address) continue
      if (!root.isWinParkedLive(win) && root.minimizeToplevel(win.address))
        parked = true
    }
    return parked
  }

  function minimizeOneWindow(entry) {
    var windows = entry ? (entry.windowList || []) : []
    var target = null

    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].address && windows[i].address === root.activeWindowAddress) {
        target = windows[i]
        break
      }
    }
    if (!target) target = root.recentWindow(entry ? entry.appId : "", windows)
    if (!target) {
      for (var j = 0; j < windows.length; j++) {
        if (windows[j] && !root.isWinParkedLive(windows[j])) {
          target = windows[j]
          break
        }
      }
    }

    return (target && target.address) ? root.minimizeToplevel(target.address) : false
  }

  // Everything the dock remembers about a window is keyed by address, so one
  // pass over the live windows is enough to drop what closed.
  function pruneWindowState() {
    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var address = root.windowAddress(list[i])
      if (address) live[address] = true
    }

    root.minimizedOrigins = root.keepLive(root.minimizedOrigins, live, false)
    root.parkedAt = root.keepLive(root.parkedAt, live, false)
    root.appRecentWindow = root.keepLive(root.appRecentWindow, live, true)
    root.urgentMap = root.keepUrgentLive(root.urgentMap, live)

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

  // urgentMap mixes two key shapes: "0x…" per-window addresses and bare appIds
  // set by the notification service. Address keys die with their window; appId
  // keys are not addresses and must survive the prune until the user clicks or focuses.
  function keepUrgentLive(map, live) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (key.slice(0, 2) === "0x" && !live[key]) dropped = true
      else next[key] = map[key]
    }
    return dropped ? next : map
  }

  function clearUrgentApp(appId, address) {
    if (!root.urgentMap) return
    var hasKeys = false
    for (var k in root.urgentMap) {
      if (root.urgentMap[k]) { hasKeys = true; break }
    }
    if (!hasKeys) return

    var map = DockModel.copyMap(root.urgentMap)
    var changed = false

    var normAddr = ""
    if (address) {
      var rawAddr = String(address).trim()
      if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
      if (rawAddr) normAddr = "0x" + rawAddr
    }

    if (normAddr && map[normAddr]) {
      delete map[normAddr]
      changed = true
    }

    var allEntries = root.pinnedSection.concat(root.runningSection)
    var targetEntries = []

    for (var i = 0; i < allEntries.length; i++) {
      var entry = allEntries[i]
      if (!entry) continue
      var entryId = entry.appId || entry.id
      var matched = false

      if (appId && (entryId === appId || DockModel.isAppMatch(entryId, appId))) {
        matched = true
      }

      if (!matched && normAddr && entry.windowList) {
        for (var w = 0; w < entry.windowList.length; w++) {
          var winAddr = entry.windowList[w] ? entry.windowList[w].address : ""
          if (winAddr && winAddr === normAddr) {
            matched = true
            break
          }
        }
      }

      if (matched) {
        targetEntries.push(entry)
      }
    }

    if (appId) {
      var rawId = DockModel.stripDesktop(appId)
      var normId = DockModel.normalizeId(appId)
      if (map[appId]) { delete map[appId]; changed = true }
      if (rawId && map[rawId]) { delete map[rawId]; changed = true }
      if (normId && map[normId]) { delete map[normId]; changed = true }
    }

    for (const target of targetEntries) {
      var targetId = target.appId || target.id
      if (targetId && map[targetId]) { delete map[targetId]; changed = true }
      if (target.id && map[target.id]) { delete map[target.id]; changed = true }
      if (target.appId && map[target.appId]) { delete map[target.appId]; changed = true }
      for (const win of target.windowList || []) {
        if (win && win.address && map[win.address]) {
          delete map[win.address]
          changed = true
        }
      }
    }

    if (appId) {
      for (var mKey in map) {
        if (mKey.slice(0, 2) !== "0x" && DockModel.isAppMatch(mKey, appId)) {
          delete map[mKey]
          changed = true
        }
      }
    }

    if (changed) {
      root.urgentMap = map
      modelTimer.restart()
    }
  }

  function keepLive(map, live, addressesAreValues) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
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

    function blur(): void { root.setBlur(!root.blurred) }
    function opacity(percent: string): void { root.setDockOpacity(percent === "auto" ? -1 : Number(percent) / 100) }
    function focus(): void { root.focusDock() }

    function restoreLast(): void {
      var parked = []
      var all = root.pinnedSection.concat(root.runningSection)
      for (var i = 0; i < all.length; i++) {
        if (!all[i]) continue
        parked = parked.concat(root.parkedWindows(all[i].windowList || []))
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
    launchPruneTimer.start()
  }

  function pruneLaunching() {
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
    if (remaining === 0) launchPruneTimer.stop()
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
    conf.itemSpacing = root.itemSpacing
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.appGroups = root.appGroups
    conf.pinnedFolders = root.pinnedFolders
    conf.recentApps = root.recentIds
    configFile.setText(JSON.stringify(conf, null, 2))
  }

  // A left click says "give me this app". It is decided from live state only —
  // which windows exist, which are parked, whether the focus is already inside the
  // app — so there is nothing to remember and nothing to go stale.
  //
  // Preferring a window on the current workspace keeps a click from teleporting you
  // while the app is already in front of you. Stepping through a multi-window app's
  // windows is what makes every click do something visible: parking one of several
  // hands focus straight to a sibling, so the app never stops being active, and both
  // a park-first and a restore-first rule end up stuck — one parks forever, the other
  // toggles one window forever. A specific window can still be parked from the
  // context menu.
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
    var hadUrgency = !!urgentWin || !!urgentParked

    if (root.urgentMap[appId]) hadUrgency = true
    root.clearUrgentApp(appId, "")

    if (urgentParked) {
      root.restoreWindow(urgentParked.address || urgentParked, appId)
      return
    }

    if (hadUrgency && focusedIdx < 0) {
      if (urgentWin && urgentWin.address) {
        root.focusWindowByAddress(urgentWin.address, appId)
        return
      }
      if (parked.length > 0) {
        root.restoreWindow(root.oldestParked(parked), appId)
        return
      }
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
      return
    }


    if (focusedIdx >= 0) {
      if (hadUrgency) {
        return
      }

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

  // Scratchpad workspaces are named special:<what>, which is far too wide for a
  // one-line row — every character there is one the title loses to elision. The
  // initial is enough to tell them apart, and it is derived rather than mapped
  // so a new scratchpad needs no change here.
  function workspaceLabel(name) {
    return DockModel.workspaceLabel(name)
  }

  function windowRowLabel(window) {
    var title = String((window && window.title) || "Window")
    var wsName = root.liveWsNameOf(window)
    // A parked window names the workspace it will return to, the way a visible
    // one names the workspace it is on. Nothing in the text marks it parked —
    // the hollow circle does that, in both the menu and the tooltip.
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
    for (i = 0; i < root.groupedSection.length; i++) {
      if (root.groupedSection[i].appId === appId || DockModel.isAppMatch(root.groupedSection[i].appId, appId))
        return root.groupedSection[i]
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
    root.refreshDock()
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
      for (var w = 0; w < allTops.length; w++) {
        var top = allTops[w]
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
    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (w && w.address) root.hyprDispatch(
        'hl.dsp.window.close({ window = "address:' + w.address + '" })',
        "closewindow address:" + w.address)
    }
  }

  function openFolderStack(path, name, cx) {
    if (root.activeStackFolder === path) {
      root.closeFolderStack()
      return
    }
    root.closeContext()
    // Kill any in-flight scan first: assigning running = true while a process
    // is already running is a no-op in Quickshell, which used to let a slow
    // older scan race the new one.
    if (folderStackScanner.running) folderStackScanner.running = false
    root.activeStackFolder = path
    root.activeStackName = name || "Folder"
    root.activeStackAnchor = cx
    root.activeStackEntries = []
    folderStackScanner.targetFolder = (path || "").replace(/^~/, Quickshell.env("HOME"))
    folderStackScanner.running = true
    root.syncVisibility()
  }

  function closeFolderStack() {
    if (folderStackScanner.running) folderStackScanner.running = false
    root.activeStackFolder = ""
    root.activeStackName = ""
    root.activeStackEntries = []
    root.syncVisibility()
  }

  FolderListModel {
    id: trashFiles
    folder: "file://" + (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"
    showHidden: true
  }
  readonly property bool trashFull: trashFiles.count > 0

  function openTrash() {
    Util.execDetached("uwsm-app -- gio open trash:///")
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

  // Links the app's own desktop entry, so autostart follows package updates.
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

  function isFolderPinned(path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      if ((list[i].path || "").replace(/^~/, Quickshell.env("HOME")) === norm) return true
    }
    return false
  }

  function toggleFolderPin(path, name, icon) {
    var next = []
    var found = false
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var folder = list[i]
      if ((folder.path || "").replace(/^~/, Quickshell.env("HOME")) === norm) {
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

  function appGroup(groupId) {
    for (var i = 0; i < root.appGroups.length; i++)
      if (root.appGroups[i] && root.appGroups[i].id === groupId) return root.appGroups[i]
    return null
  }

  function openAppGroup(group, anchor) {
    if (!group || root.activeAppGroupId === group.id) {
      root.closeAppGroup()
      return
    }
    root.closeContext()
    root.closeFolderStack()
    root.activeAppGroupId = group.id
    root.activeAppGroupData = group
    root.activeAppGroupAnchor = anchor
  }

  function closeAppGroup() {
    root.activeAppGroupId = ""
    root.activeAppGroupData = null
    root.appGroupEditing = false
  }

  function openAppGroupContext(group, anchor) {
    root.closeContext()
    root.closeFolderStack()
    root.closeAppGroup()
    root.contextAppGroupData = group
    root.contextAnchor = anchor
    root.contextAppId = "__app_group_context__"
  }

  function createAppGroup(appIds, name) {
    var apps = []
    for (var i = 0; i < appIds.length; i++) {
      var id = DockModel.normalizeId(appIds[i])
      if (id && apps.indexOf(id) < 0) apps.push(id)
    }
    if (apps.length < 2) return
    root.appGroups = root.appGroups.concat([{
      id: "group_" + Date.now(),
      name: name || "Applications",
      apps: apps
    }])
    root.setPinned(root.pinnedIds.filter(function(id) { return apps.indexOf(DockModel.normalizeId(id)) < 0 }))
    root.saveConfig()
  }

  function createAppGroupFromRunning() {
    var entries = root.pinnedSection.concat(root.runningSection)
    var apps = []
    for (var i = 0; i < entries.length; i++)
      if (entries[i] && entries[i].running && apps.indexOf(entries[i].appId) < 0) apps.push(entries[i].appId)
    root.createAppGroup(apps, "Group " + (root.appGroups.length + 1))
  }

  function addAppToGroup(groupId, appId) {
    var id = DockModel.normalizeId(appId)
    root.appGroups = root.appGroups.map(function(group) {
      if (!group || group.id !== groupId) return group
      var apps = DockModel.toArray(group.apps)
      if (apps.indexOf(id) < 0) apps.push(id)
      return Object.assign({}, group, { apps: apps })
    })
    root.setPinned(root.pinnedIds.filter(function(pin) { return !DockModel.isAppMatch(pin, id) }))
    root.saveConfig()
  }

  function removeAppFromGroup(groupId, appId, pinRemoved) {
    var groups = [], pins = root.pinnedIds.slice(), remaining = []
    for (var i = 0; i < root.appGroups.length; i++) {
      var group = root.appGroups[i]
      if (!group || group.id !== groupId) {
        groups.push(group)
        continue
      }
      remaining = DockModel.toArray(group.apps).filter(function(id) { return !DockModel.isAppMatch(id, appId) })
      if (remaining.length > 1) groups.push(Object.assign({}, group, { apps: remaining }))
      else if (remaining.length === 1 && pins.indexOf(remaining[0]) < 0) pins.push(remaining[0])
    }
    if (pinRemoved && pins.indexOf(appId) < 0) pins.push(appId)
    root.appGroups = groups
    root.setPinned(pins)
    root.saveConfig()
    var active = root.appGroup(groupId)
    if (active) root.activeAppGroupData = active
    else root.closeAppGroup()
  }

  function ungroupAppGroup(groupId) {
    var group = root.appGroup(groupId)
    if (!group) return
    var pins = root.pinnedIds.slice(), apps = DockModel.toArray(group.apps)
    for (var i = 0; i < apps.length; i++) if (pins.indexOf(apps[i]) < 0) pins.push(apps[i])
    root.appGroups = root.appGroups.filter(function(item) { return item && item.id !== groupId })
    root.setPinned(pins)
    root.saveConfig()
    root.closeAppGroup()
  }

  function renameAppGroup(groupId, name) {
    var clean = String(name || "").trim()
    if (!clean) return
    root.appGroups = root.appGroups.map(function(group) {
      return group && group.id === groupId ? Object.assign({}, group, { name: clean }) : group
    })
    root.activeAppGroupData = root.appGroup(groupId)
    root.saveConfig()
  }

  function itemMainBounds(item) {
    var point = item.mapToItem(dockCard, 0, 0)
    return { start: point.x, size: item.width }
  }

  function updateDragTarget(appId, main, away) {
    root.dropBeforeId = ""
    root.dropTargetAppId = ""
    root.dropTargetGroupId = ""
    root.dropIntoPins = false
    root.dragRemove = !!away && (DockModel.isPinned(root.pinnedIds, appId) || root.recentIds.indexOf(appId) >= 0)
    if (root.dragRemove) return

    for (var groupIndex = 0; groupIndex < appGroupsRepeater.count; groupIndex++) {
      var groupItem = appGroupsRepeater.itemAt(groupIndex)
      if (!groupItem || !groupItem.visible) continue
      var groupBounds = root.itemMainBounds(groupItem)
      if (Math.abs(main - groupBounds.start - groupBounds.size / 2) < groupBounds.size * 0.45) {
        root.dropTargetGroupId = root.appGroups[groupIndex].id
        return
      }
    }

    var count = pinnedRepeater.count
    for (var i = 0; i < count; i++) {
      var item = pinnedRepeater.itemAt(i)
      var pinnedId = root.pinnedSection[i].appId
      if (!item || !item.visible || DockModel.isAppMatch(pinnedId, appId)) continue
      var bounds = root.itemMainBounds(item)
      if (Math.abs(main - bounds.start - bounds.size / 2) < bounds.size * 0.36) {
        root.dropTargetAppId = pinnedId
        return
      }
    }
    if (count === 0) return

    var first = root.itemMainBounds(pinnedRepeater.itemAt(0))
    var last = root.itemMainBounds(pinnedRepeater.itemAt(count - 1))
    root.dropIntoPins = main >= first.start - root.gapWidth && main <= last.start + last.size + root.gapWidth
    if (!root.dropIntoPins && root.pinnedIds.indexOf(appId) < 0 && root.dragSourceGroupId === "") return

    for (var pinIndex = 0; pinIndex < count; pinIndex++) {
      var pin = pinnedRepeater.itemAt(pinIndex)
      var pinBounds = root.itemMainBounds(pin)
      if (main < pinBounds.start + pinBounds.size / 2) {
        root.dropBeforeId = root.pinnedSection[pinIndex].appId
        root.dropIndicatorMain = pinBounds.start - Style.space(1)
        return
      }
    }
    root.dropIndicatorMain = last.start + last.size + Style.space(1)
  }

  function finishDrag() {
    var appId = root.dragAppId
    var sourceGroup = root.dragSourceGroupId
    var targetGroup = root.dropTargetGroupId
    var targetApp = root.dropTargetAppId
    var before = root.dropBeforeId
    var pinHere = root.dropIntoPins
    var remove = root.dragRemove

    root.dragAppId = ""
    root.dragRemove = false
    root.dragSourceGroupId = ""
    root.dropTargetGroupId = ""
    root.dropTargetAppId = ""
    root.dropBeforeId = ""
    root.dropIntoPins = false
    if (!appId || (sourceGroup && sourceGroup === targetGroup)) return
    if (remove) {
      if (root.recentIds.indexOf(appId) >= 0) root.removeRecent(appId)
      else root.setPinned(root.pinnedIds.filter(id => id !== appId))
      return
    }

    if (sourceGroup) root.removeAppFromGroup(sourceGroup, appId, false)
    if (targetGroup) root.addAppToGroup(targetGroup, appId)
    else if (targetApp) root.createAppGroup([targetApp, appId], "Applications")
    else if (pinHere || root.pinnedIds.indexOf(appId) >= 0 || sourceGroup) {
      var pins = root.pinnedIds.slice()
      if (pins.indexOf(appId) < 0) pins.push(appId)
      root.setPinned(DockModel.reorderPinned(pins, appId, before))
    }
  }

  // Widest piece of content in the open menu. Only implicit widths are read, so
  // feeding the result back into every row cannot loop.
  function menuContentWidth(item) {
    var widest = 0
    if (!item) return widest

    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid || !kid.visible) continue
      if (kid.isMenuContent === true && kid.implicitWidth > widest) widest = kid.implicitWidth
      var nested = root.menuContentWidth(kid)
      if (nested > widest) widest = nested
    }
    return Math.min(Math.max(widest, Style.space(220)), Style.space(280))
  }


  // Back to a low threshold now that nothing paints outside the card: it only
  // has to clear the empty room the panel reserves for its popups, so even the
  // faintest opacity preset still gets its blur.
  Shell.LayerBlur { surface: "hypr-shell-dock"; enabled: root.blurred && root.dockActive; ignoreAlpha: 0.1 }

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    visible: root.dockActive
    color: "transparent"
    WlrLayershell.namespace: "hypr-shell-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Keyboard navigation holds focus exclusively: dropping to on-demand hands it
    // back to the window under the pointer.
    WlrLayershell.keyboardFocus: root.dockCursor >= 0 ? WlrKeyboardFocus.Exclusive
      : !(root.anyPanelOpen || root.appGroupEditing) ? WlrKeyboardFocus.None
      : root.menuFocusPriming || root.appGroupFocusPriming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide)
      ? Math.round(dockCard.height + Style.gapsOut)
      : 0

    // The panel spans the dock's edge and reaches well into the screen, so
    // tooltips, menus and popovers have room to open away from that edge.
    anchors {
      top: root.edge !== "bottom"
      bottom: root.edge !== "top"
      left: true
      right: true
    }
    implicitWidth: 650
    implicitHeight: 650
    Item {
      id: menuKeyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: event => event.accepted = root.handleMenuKey(event)
      Window.onActiveChanged: if (!Window.active) root.dockCursor = -1
    }

    // Bound explicitly rather than `item: dockCard`: the card slides on animated
    // x/y, and an item-tracking Region does not follow that. The input region
    // then stays where the card sat while hidden, so once the dock reveals only
    // the edge strip answers the pointer and moving onto the dock hides it again.
    mask: Region {
      x: dockCard.x
      y: dockCard.y
      width: dockCard.width
      height: dockCard.height
      regions: [
        Region { item: contextMenu },
        Region { item: folderStackPopover },
        Region { item: appGroupPopup },
        Region { item: revealStrip },
        Region { item: globalDismiss }
      ]
    }

    Item {
      id: revealStrip
      // Spelled out rather than anchored per edge: assigning undefined to the
      // anchors that do not apply does not reliably unset them, and a strip
      // left stretched across the panel reports the whole dock as an edge
      // trigger, which keeps the dock up wherever the pointer is.
      width: parent.width
      height: root.revealHeight
      y: root.edge === "bottom" ? parent.height - height : 0

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      Rectangle {
        x: (parent.width - width) / 2
        y: root.edge === "top" ? 0 : parent.height - height
        width: revealHover.hovered ? Style.space(48) : Style.space(24)
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
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
        // Accept every button: the layer-shell mask routes all clicks here
        // while a menu is open, so a right-click on empty space must dismiss
        // the menu too instead of being swallowed with no effect.
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (root.contextAppId !== "") {
            root.closeContext()
          }
          if (root.activeStackFolder !== "") {
            root.closeFolderStack()
          }
          if (root.activeAppGroupId !== "") root.closeAppGroup()
        }
        onReleased: function(mouse) {
          if (root.dragAppId !== "") root.finishDrag()
        }
      }
    }


    // Upstream sat the card on a blurred black drop shadow. Its inner rectangle
    // covered the card exactly, so it darkened the glass from behind — the card
    // read far more solid than its own opacity — and it reached 24px past every
    // edge, which is the region Hyprland was blurring outside the dock.

    BorderSurface {
      id: dockCard

      color: Util.alpha(Color.bar.background, root.effectiveDockOpacity)
      borderSpec: Border.none()
      radius: Style.cornerRadius
      padding: root.cardPadding
      topPadding: root.edge === "top" ? root.floorPadding : root.cardPadding
      bottomPadding: root.edge === "bottom" ? root.floorPadding : root.cardPadding
      z: 1

      HoverHandler {
        id: cardHover
        onHoveredChanged: root.syncVisibility()
      }

      // Centred on the main axis and inset from the dock's edge by edgeOffset,
      // which goes negative to push the card out of sight. Only that offset is
      // animated, so hiding slides while the centring stays an instant binding —
      // the card resizes continuously under the wave, and animating the centring
      // would make it lag the cursor.
      //
      // The offset has to reach x/y rather than a transform: the window mask is
      // a Region over this item, and a Region does not follow a transform, so a
      // card moved that way draws in one place and takes input in another.
      readonly property real edgeOffset: root.dockVisible
        ? Style.gapsOut
        : -(dockCard.height + Style.gapsOut + 10)
      property real slideOffset: dockCard.edgeOffset
      Behavior on slideOffset { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

      x: (parent.width - width) / 2
      y: root.edge === "top" ? slideOffset : parent.height - height - slideOffset

      opacity: root.dockVisible ? 1 : 0
      Behavior on opacity {
        NumberAnimation { duration: 180 }
      }

      width: row.implicitWidth + contentLeftInset + contentRightInset
      height: row.implicitHeight + contentTopInset + contentBottomInset

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
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
      }

      Grid {
        id: row
        z: 1
        spacing: Style.space(root.itemSpacing)
        // Empty Repeaters are visible children, so counting them adds a gap
        // after the last icon and shifts a lone button off the screen centre.
        columns: Math.max(1, root.elementTotal)

        anchors.left: parent.left
        anchors.leftMargin: dockCard.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: dockCard.contentRightInset
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
          iconContext: "actions"
          tooltip: "Applications"
          onPressed: Quickshell.execDetached(["hyprshell", "rofi-launch.sh", "d"])
          onMiddleClicked: { if (root.shell) root.shell.run([root.shell.terminal]) }
          onWheelScrolled: function(dir) { root.cycleWorkspace(dir) }
          onMenuRequested: function(cx) { root.openDockSettingsMenu(cx) }
        }

        DockSeparator { dock: root; visible: root.appsSeparatorCount > 0 }

        Repeater {
          id: pinnedRepeater
          model: root.pinnedSection
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
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx) { root.openContext(aid, cx) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }
            onDragStarted: function(aid) {
              dock.dragAppId = aid
              dock.dragSourceGroupId = ""
              dock.dropBeforeId = ""
              dock.dropTargetAppId = ""
              dock.dropTargetGroupId = ""
            }
            onDragMoved: function(aid, main, away) { dock.updateDragTarget(aid, main, away) }
            onDragDropped: function(aid) { dock.finishDrag() }
          }
        }

        Repeater {
          id: appGroupsRepeater
          model: root.appGroups
          delegate: DockAppGroupItem {
            required property var modelData
            required property int index
            dock: root
            groupData: modelData
            homeCenter: root.groupHomeCenter(index)
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

            // Same magnify contract as DockItem/DockFolderItem: wave grows the
            // layout slot; zoom scales the visual stack in place (tileVisual).
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
            // A tile is shorter than a slot across the dock and used to anchor
            // itself centred, which a Grid child may not do. The delegate now
            // fills the slot on the cross axis and centres the tile within it.
            width: tile.tileMain
            height: root.iconSlot
            opacity: root.dockVisible ? 1 : 0

            // Zoom mode scales this visual stack in place (the preview overlaps
            // neighbors exactly like magnified app icons); wave mode grows the
            // tile itself, so the wrapper stays at scale 1 there.
            Item {
              id: tileVisual
              anchors.centerIn: parent
              width: tile.tileMain
              height: root.tileCrossSize
              scale: root.waveHover ? 1 : tile.magnifyScale

              // Stacked-card layers behind grouped tiles hint at the count.
              Rectangle {
                visible: tile.isGroup && tile.groupCount > 1
                anchors.fill: parent
                anchors.leftMargin: -Style.space(3)
                anchors.bottomMargin: -Style.space(2)
                radius: root.tileRadius
                color: Util.alpha(Color.bar.text, 0.16)
                border.width: 1
                border.color: Util.alpha(Color.bar.text, 0.38)
              }
              Rectangle {
                visible: tile.isGroup && tile.groupCount > 2
                anchors.fill: parent
                anchors.leftMargin: -Style.space(6)
                anchors.bottomMargin: -Style.space(4)
                radius: root.tileRadius
                color: Util.alpha(Color.bar.text, 0.11)
                border.width: 1
                border.color: Util.alpha(Color.bar.text, 0.28)
              }

              Rectangle {
                anchors.fill: parent
                radius: root.tileRadius
                color: tileArea.containsMouse ? Color.menu.selectedBackground : Util.alpha(Color.bar.text, 0.10)
                border.width: 1
                border.color: Util.alpha(Color.bar.text, tileArea.containsMouse ? 0.55 : 0.22)
              }

              // The capture fills the frame and the overflow is trimmed, rather
              // than being fitted inside it and leaving bars. Both axes still
              // come off the source, so the scale stays uniform and nothing is
              // stretched — Math.max covers where Math.min would contain. The
              // layer both clips that overflow and carries the rounded mask, so
              // the corners match the frame.
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

                // The capture context negotiates asynchronously over Wayland,
                // so an immediate captureFrame() warns "no recording context".
                // A short event-driven retry (never a polling loop) gets every
                // tile its frame exactly once, after the session is ready.
                onCaptureSourceChanged: {
                  captureRetry.attempts = 0
                  captureRetry.restart()
                }
                // Failed exports emit stopped, which destroys the Wayland
                // capture context. Null-then-restore forces createContext()
                // via setCaptureSource; Qt.callLater avoids double-triggering
                // onCaptureSourceChanged in the same event loop tick.
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

              // Rounded stencil, matching the frame's corners.
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
                width: Style.space(tile.groupCount > 1 ? 18 : 14)
                height: Style.space(tile.groupCount > 1 ? 18 : 14)
                radius: Style.space(3)
                color: Util.alpha(Color.bar.background, 0.85)

                Text {
                  anchors.centerIn: parent
                  text: {
                    if (!tile.win || !tile.win.appId) return "?"
                    return tile.groupCount > 1 ? String(tile.groupCount) : tile.win.appId.substring(0, 1).toUpperCase()
                  }
                  textFormat: Text.PlainText
                  color: Color.bar.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            BorderSurface {
              id: tileTooltip
              visible: tile.tileHovered && !tile.tileMenuOpen && tile.tileTitle !== ""
              z: root.tooltipZ
              color: Util.alpha(Color.tooltip.background, Style.popupSurfaceOpacity)
              borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
              radius: Style.cornerRadius
              padding: Style.space(4)
              x: (parent.width - width) / 2
              y: root.tipY(parent.height, height, Style.space(6))
              width: tileTooltipLabel.implicitWidth + contentLeftInset + contentRightInset
              height: tooltipImplicitHeight()

              function tooltipImplicitHeight() {
                return tileTooltipLabel.implicitHeight + contentTopInset + contentBottomInset
              }

              Text {
                id: tileTooltipLabel
                x: parent.contentLeftInset
                y: parent.contentTopInset
                text: {
                  if (!tile.isGroup) return tile.tileTitle
                  var lines = []
                  var max = Math.min(tile.groupWins.length, root.maxGroupTooltipLines)
                  for (var i = 0; i < max; i++) lines.push("• " + (tile.groupWins[i] ? tile.groupWins[i].title : ""))
                  if (tile.groupWins.length > root.maxGroupTooltipLines) lines.push("+" + (tile.groupWins.length - root.maxGroupTooltipLines) + " more")
                  return lines.join("\n")
                }
                textFormat: Text.PlainText
                color: Color.tooltip.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
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
          model: root.runningSection
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
            // Wave geometry must count only icons that actually render — a
            // hidden (fully-tiled) entry occupies zero width in the Row.
            homeCenter: root.runningHomeCenter(index)
            pinned: false
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx) { root.openContext(aid, cx) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }
            onDragStarted: function(aid) {
              dock.dragAppId = aid
              dock.dragSourceGroupId = ""
            }
            onDragMoved: function(aid, main, away) { dock.updateDragTarget(aid, main, away) }
            onDragDropped: function(aid) { dock.finishDrag() }

            // When an unpinned app has ALL its windows minimized and tiles are
            // showing, the tile section already represents it — hide the icon
            // slot entirely so only the tile (with hollow dot) is visible.
            // Live resolver: same source as the running-dot indicator, so the
            // icon can never outlive its own tile after a lagged park.
            readonly property bool isFullyTiled: root.showMinimizedTiles
              && DockModel.allWindowsMinimized(modelData.windowList, root.liveWsNameOf, root.isMinimizedWorkspace)
            visible: !isFullyTiled

            // Row preserves space for invisible items that have explicit width.
            // Collapse to 0 when hidden so the dock card shrinks correctly.
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
          && root.dropTargetAppId === "" && root.dropTargetGroupId === ""
        x: root.dropIndicatorMain
        y: row.y + (row.height - height) / 2
        width: Style.space(2)
        height: root.iconSize + Style.space(4)
        radius: 1
        color: Color.bar.active
        z: 10
      }
    }

    AppGroupPopup {
      id: appGroupPopup
      dock: root
    }

    BorderSurface {
      id: folderStackPopover
      visible: root.activeStackFolder !== "" && root.dockVisible
      opacity: (root.activeStackFolder !== "" && root.dockVisible) ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      z: root.popoverZ
      color: Util.alpha(Color.menu.background, Style.popupSurfaceOpacity)
      borderSpec: Border.surfaceSpec("menu", "border",
        Util.alpha(Color.menu.border, Style.popupBorderOpacity), 1)
      radius: Style.cornerRadius
      padding: Style.space(4)

      HoverHandler { id: stackHover }

      readonly property real rowWidth: root.activeStackFolder !== ""
        ? root.menuContentWidth(stackColumn)
        : 0

      width: root.activeStackFolder !== ""
        ? rowWidth + contentLeftInset + contentRightInset
        : 0
      height: root.activeStackFolder !== ""
        ? stackColumn.implicitHeight + contentTopInset + contentBottomInset
        : 0

      x: root.panelX(width, root.activeStackAnchor)
      y: root.panelY(height)

      Column {
        id: stackColumn
        spacing: Style.space(2)

        anchors.left: parent.left
        anchors.leftMargin: folderStackPopover.contentLeftInset
        anchors.right: parent.right
        anchors.rightMargin: folderStackPopover.contentRightInset
        anchors.top: parent.top
        anchors.topMargin: folderStackPopover.contentTopInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: folderStackPopover.contentBottomInset

        ContextRow {
          text: (root.activeStackName || "Folder") + (root.activeStackTotalCount > 0 ? (" (" + root.activeStackTotalCount + ")") : "")
          isHeader: true
        }

        Text {
          visible: root.activeStackEntries.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Folder is empty"
          textFormat: Text.PlainText
          color: Util.alpha(Color.menu.text, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          padding: Style.space(8)
        }

        Repeater {
          model: root.activeStackEntries.slice(0, 16)
          delegate: FileStackRow {
            required property var modelData
            dock: root
            menuWidth: folderStackPopover.rowWidth
            name: modelData.name
            path: modelData.path
            icon: modelData.icon
            subtext: modelData.size
            onTriggered: {
              Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(modelData.path))
              root.closeFolderStack()
            }
          }
        }

        // The scanner caps at 16 entries; tell the user when the folder holds
        // more instead of silently truncating.
        ContextRow {
          visible: root.activeStackTotalCount > root.activeStackEntries.length
          text: "+ " + (root.activeStackTotalCount - root.activeStackEntries.length) + " more — open in File Manager"
          onTriggered: {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.activeStackFolder.replace(/^~/, Quickshell.env("HOME"))))
            root.closeFolderStack()
          }
        }

        MenuDivider {
          visible: root.activeStackTotalCount > root.activeStackEntries.length
        }

        ContextRow {
          text: "Open in File Manager"
          onTriggered: {
            Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(root.activeStackFolder.replace(/^~/, Quickshell.env("HOME"))))
            root.closeFolderStack()
          }
        }
        Text {
          width: parent.width; text: "↑↓ move · Enter open · ←/Esc close"
          wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter
          fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, Style.font.caption - 2)
          color: Util.alpha(Color.menu.text, .55)
          font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
    }
    DockContextMenu {
      id: contextMenu
      dock: root
    }
  }
}

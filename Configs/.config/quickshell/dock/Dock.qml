import QtQuick
import QtQuick.Effects
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

  property var shell: null
  property alias contextSelectedWindowIdx: contextMenu.selectedWindowIdx

  readonly property string dockPath: Quickshell.env("HOME") + "/.config/quickshell/dock/pins.json"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/dock/settings.json"


  // The edge, transparency and blur the dock uses when it is not following the
  // bar. Linked, all three come from the bar instead, and toggling either side
  // writes through to the bar's store so the two never drift apart.
  property string dockEdge: "bottom"
  property bool dockTransparent: false
  property bool dockBlur: true
  property bool linkToBar: true

  readonly property var barStore: (root.shell && root.shell.store) ? root.shell.store : null
  readonly property bool linked: root.linkToBar && root.barStore !== null
  readonly property bool transparent: root.linked ? root.barStore.barTransparent === true : root.dockTransparent
  readonly property bool blurred: root.linked ? root.barStore.barBlur === true : root.dockBlur

  function setTransparent(value) {
    if (root.linked) root.barStore.barTransparent = value
    else { root.dockTransparent = value; root.saveConfig() }
  }
  function setBlur(value) {
    if (root.linked) root.barStore.barBlur = value
    else { root.dockBlur = value; root.saveConfig() }
  }
  function setLinkToBar(value) {
    // Unlinking keeps whatever is on screen, so the dock does not jump.
    if (!value) {
      root.dockEdge = root.edge
      root.dockTransparent = root.transparent
      root.dockBlur = root.blurred
    }
    root.linkToBar = value
    root.saveConfig()
  }
  function setDockEdge(value) {
    root.dockEdge = value
    if (root.linkToBar) root.linkToBar = false
    root.saveConfig()
  }

  // Each bar layout pins the bar to one screen edge; linked, the dock takes the
  // opposite one so the two never share a side.
  readonly property string barEdge: root.shell ? String(root.shell.barEdge) : "top"
  readonly property string edge: root.linkToBar
    ? ({ top: "bottom", bottom: "top", left: "right", right: "left" })[root.barEdge]
    : root.dockEdge
  // Main axis is the one icons march along; cross axis is the card's thickness.
  readonly property bool vertical: root.edge === "left" || root.edge === "right"
  readonly property real mainWindowSize: root.vertical ? dockWindow.height : dockWindow.width
  readonly property real cardMainInsetStart: root.vertical ? dockCard.contentTopInset : dockCard.contentLeftInset
  readonly property real cardMainInsetEnd: root.vertical ? dockCard.contentBottomInset : dockCard.contentRightInset
  // The dock's "floor" is the side facing its screen edge: icons stand on it,
  // indicators line it, and a launch bounce lifts away from it. awaySign turns
  // the bounce's own negative magnitude into that outward direction.
  readonly property int awaySign: (root.edge === "bottom" || root.edge === "right") ? 1 : -1
  readonly property int floorTransformOrigin: root.edge === "bottom" ? Item.Bottom
    : root.edge === "top" ? Item.Top : root.edge === "left" ? Item.Left : Item.Right

  // A hover bubble hangs off the slot's non-floor side, centred on the main axis.
  function tipX(hostWidth, tipWidth, gap) {
    var g = gap || Style.space(8)
    if (root.edge === "left") return hostWidth + g
    if (root.edge === "right") return -tipWidth - g
    return (hostWidth - tipWidth) / 2
  }
  // A panel that opens off the dock clears the card on the cross axis and
  // centres on the main-axis point its opener reported, clamped to the screen.
  readonly property real panelGap: Style.space(6)
  function panelMain(size, at) {
    return Math.max(Style.gapsOut,
                    Math.min(root.mainWindowSize - size - Style.gapsOut, at - size / 2))
  }
  function panelCross(size) {
    if (root.edge === "bottom") return dockCard.y - size - root.panelGap
    if (root.edge === "top") return dockCard.y + dockCard.height + root.panelGap
    if (root.edge === "left") return dockCard.x + dockCard.width + root.panelGap
    return dockCard.x - size - root.panelGap
  }

  function tipY(hostHeight, tipHeight, gap) {
    var g = gap || Style.space(8)
    if (root.edge === "top") return hostHeight + g
    if (root.edge === "bottom") return -tipHeight - g
    return (hostHeight - tipHeight) / 2
  }

  property string screenName: ""
  readonly property var dockScreen: root.screenName
    ? root.screenForName(root.screenName)
    : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

  function screenForName(name) {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++)
      if (list[i].name === name) return list[i]
    return null
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
  readonly property real magnifyPeak: 1.4
  readonly property real zoomPeak: 1.22
  readonly property real magnifyRange: root.iconSlot * 2.2
  readonly property real baseIconArt: root.iconSize - Style.space(4)

  // The card's own handler, lifted into window coordinates. Both terms move
  // together as the card grows, so their sum stays the physical pointer.
  readonly property real pointerMain: cardHover.hovered
    ? (root.vertical ? dockCard.y + cardHover.point.position.y
                     : dockCard.x + cardHover.point.position.x)
    : -1e6

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
  readonly property bool hasSeparator: root.pinnedSection.length > 0 && root.visibleRunningCount > 0
  readonly property real gapWidth: Style.space(root.itemSpacing)
  readonly property real separatorWidth: Style.space(1)
  readonly property int folderSlots: root.pinnedFolders ? root.pinnedFolders.length : 0
  readonly property bool hasFolderSeparator: root.folderSlots > 0 && (root.pinnedSection.length > 0 || root.visibleRunningCount > 0)

  // Minimized-window preview tiles (macOS-style section on the dock's right).
  // In minimizeMode "all", a parked app's windows compress into ONE stacked
  // group tile; in "active" mode every window keeps its own tile.
  readonly property var tileModel: {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      var singles = []
      for (var s = 0; s < list.length; s++) singles.push({ type: "single", win: list[s] })
      return singles
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
    order.sort(function (a, b) {
      var ta = root.parkedAt[groups[a].windows[0].address] !== undefined ? root.parkedAt[groups[a].windows[0].address] : 0
      var tb = root.parkedAt[groups[b].windows[0].address] !== undefined ? root.parkedAt[groups[b].windows[0].address] : 0
      return ta - tb
    })
    var out = []
    for (var g = 0; g < order.length; g++) out.push(groups[order[g]])
    return out
  }
  readonly property int tileCount: root.tileModel.length
  // The tile frame stays landscape on every edge. Its short side is the one
  // that crosses the dock, so the dock never grows thicker than its icons; the
  // long side runs along the dock when horizontal, and across it when vertical —
  // where the dock's own thickness caps it, making the whole tile smaller.
  // Named for the axes rather than width/height, since which is which flips.
  readonly property real tileAspect: 1.5 / 0.95
  readonly property real tileCrossSize: Math.round(root.iconSlot * 0.95)
  readonly property real tileMainSize: root.vertical
    ? Math.round(root.tileCrossSize / root.tileAspect)
    : Math.round(root.iconSlot * 1.5)

  // Tiles take the dock's own rounding rather than a fixed 4px, clamped to half
  // the tile's short side so a large theme radius cannot round one into a pill.
  readonly property real tileRadius: {
    if (root.dockShape === "square") return 0
    var limit = Math.min(root.tileMainSize, root.tileCrossSize) / 2
    if (root.dockShape === "round" || root.dockShape === "pill") return limit
    return Math.max(2, Math.min(limit, root.effectiveCardRadius))
  }
  readonly property bool hasTiles: root.tileCount > 0
  // Left tile divider (pinned|tiles) renders only when pins precede the tiles.
  readonly property bool hasLeftTileSeparator: root.hasTiles && root.pinnedSection.length > 0

  // Width arithmetic total: hidden (fully-tiled) entries occupy zero width,
  // so the row-width and gap math must count only visible icons.
  readonly property int visibleSlotTotal: root.appsSlots + root.pinnedSection.length + root.visibleRunningCount + root.folderSlots
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
  readonly property real baseRowStart: (root.mainWindowSize
    - (root.baseRowWidth + root.cardMainInsetStart + root.cardMainInsetEnd)) / 2
    + root.cardMainInsetStart

  function slotHomeCenter(elementIndex, slotsBefore, sepCount, extraLeftWidth) {
    var seps = (typeof sepCount === "number") ? sepCount : (sepCount ? 1 : 0)
    return root.baseRowStart
      + elementIndex * root.gapWidth
      + slotsBefore * root.iconSlot
      + seps * root.separatorWidth
      + (extraLeftWidth || 0)
      + root.iconSlot / 2
  }

  // Width the tile section consumes ahead of elements that follow it,
  // including its left divider.
  readonly property real tilesFixedWidth: root.hasTiles
    ? (root.hasLeftTileSeparator ? root.separatorWidth : 0) + root.tileCount * root.tileMainSize
    : 0
  readonly property int tileElements: root.hasTiles ? root.tileCount : 0

  function magnifyAt(homeCenter) {
    if (!root.waveHover) return 0
    var distance = root.pointerMain - homeCenter
    if (Math.abs(distance) >= root.magnifyRange) return 0
    return 0.5 * (1 + Math.cos(Math.PI * distance / root.magnifyRange))
  }

  function magnifyScaleAt(homeCenter) {
    return 1 + (root.magnifyPeak - 1) * root.magnifyAt(homeCenter)
  }


  // The bar foreground is tuned for the bar's own background. A custom dock
  // colour can land on the same side of the scale — a light theme's dark text
  // on a dark card, or the reverse — so flip only when the two collide.
  function isLight(value) {
    return (0.2126 * value.r + 0.7152 * value.g + 0.0722 * value.b) > 0.5
  }

  // Corner radius for the dock card. "rounded" tracks the card's own height, so
  // the panel keeps the same visual softness at any icon size.
  readonly property int effectiveCardRadius: {
    var h = dockCard.height > 0 ? dockCard.height : (root.iconSlot + Style.space(10))
    if (root.dockShape === "round" || root.dockShape === "pill") return Math.round(h / 2)
    if (root.dockShape === "square") return 0
    if (root.dockShape === "theme" || root.dockShape === "auto") {
      var n = Style.cornerRadius
      return (typeof n === "number" && isFinite(n) && n >= 0) ? n : Math.max(14, Style.space(14))
    }
    return Math.max(Style.space(14), Math.min(Style.space(28), Math.round(h * 0.26)))
  }

  function cardRadius(height) {
    return root.effectiveCardRadius
  }

  readonly property color dockForeground: {
    var custom = String(root.dockBgColor || "")
    if (custom.charAt(0) !== "#") return Color.bar.text

    // A hand-edited config can hold an invalid hex string; Qt.color() throws
    // on those, which would break this binding and take the whole dock's
    // foreground with it. Fall back to the theme color instead.
    var customColor
    try {
      customColor = Qt.color(custom)
    } catch (e) {
      return Color.bar.text
    }
    var cardIsLight = root.isLight(customColor)
    if (cardIsLight !== root.isLight(Color.bar.text)) return Color.bar.text
    return cardIsLight ? "#12100f" : "#f2efec"
  }


  property int configuredIconSize: 0
  readonly property int iconSize: root.configuredIconSize > 0
    ? root.configuredIconSize
    : Math.max(28, Math.round(Style.bar.sizeHorizontal * 0.9))
  readonly property int iconSlot: root.iconSize + Style.space(10)


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

  function refreshDock() {
    root.dockModel = DockModel.buildEntries(root.pinnedIds,
                                            (ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []),
                                            root.appRows, root.appLibrary, root.hyprToplevelFor,
                                            root.isMinimizedWorkspace, root.minimizedOrigins)
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
    mins.sort(function (a, b) {
      var ta = root.parkedAt[a.address] !== undefined ? root.parkedAt[a.address] : 0
      var tb = root.parkedAt[b.address] !== undefined ? root.parkedAt[b.address] : 0
      return ta - tb
    })
    // Assign only on real change: a fresh array per rebuild would recreate
    // every tile delegate on unrelated events, eating clicks and forcing
    // pointless capture re-negotiations.
    var sig = ""
    for (var s = 0; s < mins.length; s++) sig += mins[s].address + ","
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

  // Apps whose launch has been asked for but whose window has not shown up yet.
  property var launchPending: ({})
  readonly property int launchTimeout: 12000


  property string dragAppId: ""
  property string dropBeforeId: ""
  property real dropIndicatorX: 0


  property string contextAppId: ""
  property string contextName: ""
  property bool contextPinned: false
  property int contextWindows: 0
  property var contextWindowList: []
  property var contextDesktopActions: []
  property real contextAnchor: 0
  property real contextY: 0


  property var pinnedFolders: []
  property string activeStackFolder: ""
  property string activeStackName: ""
  property var activeStackEntries: []
  property int activeStackTotalCount: 0
  property real activeStackAnchor: 0
  property string contextFolderPath: ""
  property string contextFolderName: ""


  property bool autohide: true
  property bool intelligentAutohide: true
  property bool showAppsButton: true
  property bool showTooltips: true
  property bool showMinimizedTiles: true
  // "zoom" grows only the icon under the pointer and leaves the layout alone —
  // the behaviour this dock shipped with, and the default. "wave" is the
  // falloff: neighbours respond and the row carries the extra width. "off" is
  // no hover growth at all.
  property string hoverEffect: "zoom"
  readonly property bool waveHover: root.hoverEffect === "wave"
  property bool launchBounce: true
  property bool advancedTooltips: true
  property real dockOpacity: 1.0
  // Every surface the dock draws — card, menus, popover, tooltips — sits at the
  // same opacity, so the menus do not read as a denser material than the dock
  // they belong to. PopupCard's 0.92 is right for a free-standing popup over
  // arbitrary content; a dock menu is part of the dock.
  readonly property real dockSurfaceOpacity: Math.max(0.45, root.effectiveDockOpacity)

  readonly property real effectiveDockOpacity: {
    if (root.dockOpacity < 0) {
      // "Auto (Theme)" means match the bar. Upstream reads the alpha off
      // Color.bar.background, but this config's palette colours are opaque and
      // the bar applies its opacity itself, so that resolved to 1 and left the
      // dock the only solid surface on the desktop.
      var a = Style.barOpacity
      if (!isFinite(a) || a < 0) {
        a = (Color.bar && Color.bar.background && typeof Color.bar.background.a === "number") ? Color.bar.background.a : 1.0
      }
      return (isFinite(a) && a >= 0) ? Math.min(1.0, a) : 1.0
    }
    return Math.max(0.0, Math.min(1.0, root.dockOpacity))
  }
  property string dockShape: "rounded"
  property string dockBgColor: "theme"
  property int themeVersion: 0
  property string folderColor: "theme"
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

  // Reactive, debounced overlap check — zero CPU polling loops
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
    for (var t = 0; t < tops.length; t++) {
      var ipc = tops[t] ? tops[t].lastIpcObject : null
      if (ipc) clients.push(ipc)
    }

    // Logical monitor dimensions accounting for fractional scaling.
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
    var scale = (mon && mon.scale > 0)
      ? mon.scale
      : (dockScreen && dockScreen.devicePixelRatio ? dockScreen.devicePixelRatio : 1.0)
    var screenLogicalW = (mon && mon.width > 0)
      ? (mon.width / scale)
      : (dockScreen ? dockScreen.width : 1920)
    var screenLogicalH = (mon && mon.height > 0)
      ? (mon.height / scale)
      : (dockScreen ? dockScreen.height : 1080)

    var cardW = dockCard.width > 0 ? (dockCard.width + Style.gapsOut * 2) : 320
    var cardH = dockCard.height > 0 ? (dockCard.height + Style.gapsOut * 2) : 60
    var monX = (mon && typeof mon.x === "number") ? mon.x : 0
    var monY = (mon && typeof mon.y === "number") ? mon.y : 0
    // The card's footprint on the dock's own edge, in monitor coordinates.
    var dockLeft, dockRight, dockTop, dockBottom
    if (root.vertical) {
      dockTop = monY + (screenLogicalH - cardH) / 2
      dockBottom = monY + (screenLogicalH + cardH) / 2
      if (root.edge === "left") {
        dockLeft = monX
        dockRight = monX + cardW + 12
      } else {
        dockLeft = monX + screenLogicalW - cardW - 12
        dockRight = monX + screenLogicalW
      }
    } else {
      dockLeft = monX + (screenLogicalW - cardW) / 2
      dockRight = monX + (screenLogicalW + cardW) / 2
      if (root.edge === "top") {
        dockTop = monY
        dockBottom = monY + cardH + 12
      } else {
        dockTop = monY + screenLogicalH - cardH - 12
        dockBottom = monY + screenLogicalH
      }
    }

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
      var c = clients[i]
      if (!c.mapped || c.hidden) continue
      if (!c.workspace) continue
      if (c.workspace.id !== dockWsId
        && !(dockSpecialWs !== "" && String(c.workspace.name || "") === dockSpecialWs)) continue

      var at = c.at
      var sz = c.size
      if (!at || !sz || at.length < 2 || sz.length < 2) continue

      var winLeft = at[0]
      var winTop = at[1]
      var winRight = at[0] + sz[0]
      var winBottom = at[1] + sz[1]

      var intersectsX = (winRight >= dockLeft) && (winLeft <= dockRight)
      var intersectsY = (winBottom >= dockTop) && (winTop <= dockBottom)

      if (intersectsX && intersectsY) {
        overlap = true
        break
      }
    }

    root.windowsOverlapDock = overlap
  }

  Process {
    id: folderStackScanner
    property string targetFolder: ""
    command: ["python3", "-c", "import os, json, time, sys\nfolder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else ''\nif not folder or not os.path.exists(folder):\n    print(json.dumps({'count':0,'items':[],'folder':folder}))\n    sys.exit(0)\nentries = []\ntry:\n    for entry in os.scandir(folder):\n        try:\n            if entry.name.startswith('.'):\n                continue\n            stat = entry.stat()\n            is_dir = entry.is_dir()\n            size_bytes = stat.st_size if not is_dir else 0\n            if size_bytes < 1024:\n                size_str = f'{size_bytes} B'\n            elif size_bytes < 1024 * 1024:\n                size_str = f'{size_bytes / 1024:.1f} KB'\n            elif size_bytes < 1024 * 1024 * 1024:\n                size_str = f'{size_bytes / (1024 * 1024):.1f} MB'\n            else:\n                size_str = f'{size_bytes / (1024 * 1024 * 1024):.1f} GB'\n            diff = time.time() - stat.st_mtime\n            if diff < 60:\n                time_str = 'Just now'\n            elif diff < 3600:\n                time_str = f'{int(diff // 60)}m ago'\n            elif diff < 86400:\n                time_str = f'{int(diff // 3600)}h ago'\n            else:\n                time_str = f'{int(diff // 86400)}d ago'\n            ext = os.path.splitext(entry.name)[1].lower()\n            is_img = ext in ['.png', '.jpg', '.jpeg', '.webp', '.svg', '.gif']\n            if is_dir:\n                icon = 'folder'\n            elif is_img:\n                icon = 'image-x-generic'\n            elif ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi']:\n                icon = 'video-x-generic'\n            elif ext in ['.mp3', '.flac', '.wav', '.ogg', '.m4a']:\n                icon = 'audio-x-generic'\n            elif ext in ['.zip', '.tar', '.gz', '.xz', '.7z', '.rar']:\n                icon = 'package-x-generic'\n            elif ext in ['.pdf']:\n                icon = 'application-pdf'\n            elif ext in ['.txt', '.md', '.json', '.qml', '.py', '.cpp', '.js', '.lua', '.rs', '.go', '.html', '.css']:\n                icon = 'text-x-generic'\n            else:\n                icon = 'application-x-executable'\n            entries.append({'name': entry.name, 'path': entry.path, 'isDir': is_dir, 'isImage': is_img, 'size': size_str, 'time': time_str, 'mtime': stat.st_mtime, 'icon': icon})\n        except Exception:\n            pass\nexcept Exception:\n    pass\nentries.sort(key=lambda x: x['mtime'], reverse=True)\nprint(json.dumps({'count': len(entries), 'items': entries[:16], 'folder': folder}))\n", folderStackScanner.targetFolder]
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

  Process {
    id: customFolderPickerProc
    command: ["python3", "-c", "import gi\ngi.require_version('Gtk', '3.0')\nfrom gi.repository import Gtk\ndialog = Gtk.FileChooserDialog(title='Select Folder to Pin to Dock', action=Gtk.FileChooserAction.SELECT_FOLDER)\ndialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)\nres = dialog.run()\nif res == Gtk.ResponseType.OK:\n    print(dialog.get_filename())\ndialog.destroy()\n"]
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
  readonly property bool anyPanelOpen: root.contextAppId !== "" || root.activeStackFolder !== ""
  readonly property string startPopupName: "dockstart"
  readonly property bool startPopupOpen: root.shell ? root.shell.popupName === root.startPopupName : false

  onStartPopupOpenChanged: root.syncVisibility()
  onPointerOverDockChanged: root.syncPanelDismiss()
  onAnyPanelOpenChanged: root.syncPanelDismiss()

  // A menu or popover is anchored to the slot that opened it, so moving onto a
  // different slot strands it beside a neighbour it has nothing to do with.
  // Dragging is exempt: the pointer crosses every slot on its way.
  function slotEntered(menuOwner, stackOwner) {
    if (root.dragAppId !== "") return
    if (root.contextAppId !== "" && root.contextAppId !== menuOwner) root.closeContext()
    if (root.activeStackFolder !== "" && root.activeStackFolder !== stackOwner) root.closeFolderStack()
  }

  function syncPanelDismiss() {
    if (root.pointerOverDock || !root.anyPanelOpen || root.dragAppId !== "") panelLeaveTimer.stop()
    else panelLeaveTimer.restart()
  }

  Timer {
    id: panelLeaveTimer
    interval: 350
    onTriggered: {
      if (root.pointerOverDock || root.dragAppId !== "") return
      if (root.contextAppId !== "") root.closeContext()
      if (root.activeStackFolder !== "") root.closeFolderStack()
    }
  }

  function syncVisibility() {
    if (!root.autohide) {
      hideTimer.stop()
      revealTimer.stop()
      root.dockVisible = true
      return
    }

    var isHovered = (cardHover && cardHover.hovered) || (revealHover && revealHover.hovered)
      || root.contextAppId !== "" || root.dragAppId !== "" || root.activeStackFolder !== ""
      || root.startPopupOpen

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

  onContextAppIdChanged: root.syncVisibility()
  onActiveStackFolderChanged: root.syncVisibility()
  onDragAppIdChanged: root.syncVisibility()
  onAutohideChanged: root.syncVisibility()
  onIntelligentAutohideChanged: {
    if (root.intelligentAutohide) debounceOverlapTimer.restart()
    root.syncVisibility()
  }
  onWindowsOverlapDockChanged: root.syncVisibility()
  onDockVisibleChanged: {
    if (root.dockVisible && root.shell) root.shell.cycleDistroGlyph()
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
            for (var w = 0; w < wins.length; w++) {
              var wa = wins[w] ? wins[w].address : ""
              if (wa && wa === fullAddr) {
                return
              }
            }
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
          var mo = DockModel.copyMap(root.minimizedOrigins)
          delete mo[fullAddr]
          root.minimizedOrigins = mo
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
    root.dockShape = parsed && typeof parsed.shape === "string" ? parsed.shape : "rounded"
    root.dockBgColor = parsed && typeof parsed.bgColor === "string" ? parsed.bgColor : "theme"
    root.folderColor = parsed && typeof parsed.folderColor === "string" ? parsed.folderColor : "theme"
    root.linkToBar = parsed ? parsed.linkToBar !== false : true
    root.dockEdge = parsed && typeof parsed.edge === "string" ? parsed.edge : "bottom"
    root.dockTransparent = parsed ? parsed.transparent === true : false
    root.dockBlur = parsed ? parsed.blur !== false : true
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
  // icon theme, which is not installed here, so only the modes that recolour
  // Adwaita's symbolic folder remain.
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

  function openDockSettingsMenu(x, y) {
    root.contextName = "Dock Settings"
    root.contextWindows = 0
    root.contextWindowList = []
    root.contextPinned = false
    root.contextAnchor = x
    root.contextY = y
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

  function setDockShape(shape) {
    root.dockShape = shape
    root.saveConfig()
  }

  function setDockBgColor(col) {
    root.dockBgColor = col
    root.saveConfig()
  }

  function setIconSize(sz) {
    root.configuredIconSize = sz
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

  // Wheel over the apps button walks workspaces in order. "e+1"/"e-1" are
  // standard Hyprland workspace selectors (nearest existing, relative).
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

  // Brings a window forward cleanly. Native Wayland activation hands over focus
  // and brings the window forward without warping the mouse pointer away from the dock
  // or desynchronizing layer-shell input state. Switches workspace when target is on another workspace.
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
    return true
  }

  function restoreWindow(targetRef, appId, useOrigin) {
    var address = typeof targetRef === "string" ? targetRef : root.windowAddress(targetRef)
    if (!address) return false


    // Default restore target is the workspace the user is on right now;
    // useOrigin=true sends the window back to where it was parked from.
    var origin = root.minimizedOrigins[address] || ""
    var target = ""
    if ((useOrigin || root.isScratchpadWorkspace(origin)) && origin) target = origin
    if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
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
    root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(target) + '" })',
                      "workspace " + target)

    var top = root.liveToplevelForAddress(address)
    if (top) {
      DockModel.focusWindow(top)
    }
    return true
  }

  // Restores a group of windows in one compositor transaction:
  // all moves are dispatched silently first, then workspace focus and window
  // activation happen exactly once. This prevents the "one-by-one fullscreen"
  // flash that occurs when restoreWindow() is called in a loop (each call
  // previously triggered its own focus switch and Wayland activation).
  //
  // primaryAddress: the window to focus after all moves. When null/undefined,
  // the most-recently-parked window (highest parkedAt timestamp) is chosen.
  //
  // useOrigin: when true, each window returns to the workspace it was parked
  // from (minimizedOrigins). Default restores everything onto the user's
  // currently active workspace.
  function restoreWindowBatch(wins, primaryAddress, useOrigin) {
    if (!wins || wins.length === 0) return

    // Single-copy the maps — O(n) instead of O(n²) individual copies.
    var origins = DockModel.copyMap(root.minimizedOrigins)
    var parkedTimes = DockModel.copyMap(root.parkedAt)

    var focusAddr = null
    var focusTarget = null
    var bestTime = -1

    for (var i = 0; i < wins.length; i++) {
      var w = wins[i]
      if (!w || !w.address) continue
      var address = w.address

      var origin = origins[address] || ""
      var target = ""
      if ((useOrigin || root.isScratchpadWorkspace(origin)) && origin) target = origin
      if (!target) target = root.workspaceTarget(Hyprland.focusedWorkspace)
      if (!target) continue

      var t = parkedTimes[address] !== undefined ? parkedTimes[address] : 0
      delete origins[address]
      delete parkedTimes[address]

      // Silent move only — no workspace switch or window focus per iteration.
      root.hyprDispatch(
        'hl.dsp.window.move({ window = "address:' + address + '", workspace = "'
          + root.luaString(target) + '", follow = false })',
        "movetoworkspacesilent " + target + ",address:" + address)

      // Track which window to focus: explicit override first, then most-recently-parked.
      if (primaryAddress && address === primaryAddress) {
        focusAddr = address
        focusTarget = target
        bestTime = Infinity
      } else if (bestTime !== Infinity && t >= bestTime) {
        bestTime = t
        focusAddr = address
        focusTarget = target
      }
    }

    // Commit map mutations once.
    root.minimizedOrigins = origins
    root.parkedAt = parkedTimes

    // Single workspace switch + single window activation after all moves.
    if (focusTarget) {
      root.hyprDispatch('hl.dsp.focus({ workspace = "' + root.luaString(focusTarget) + '" })',
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

  // The window an app should act on: the one it was last focused in, as long as
  // it is still around and not parked.
  function windowByAddress(windows, address) {
    return DockModel.windowByAddress(windows, address, root.isWinParkedLive)
  }

  // The app's windows that are still on screen, in window order.
  function visibleWindows(windows) {
    return DockModel.windowsByParkedState(windows, root.isWinParkedLive, false)
  }

  // Which of these windows holds the focus, if any.
  function focusedIndex(windows) {
    return DockModel.focusedIndex(windows, root.activeWindowAddress)
  }

  // A window of this app on the workspace you are looking at.
  function windowHere(windows) {
    return DockModel.windowOnWorkspace(windows, root.liveWsNameOf,
      root.focusedWorkspaceId, root.focusedWorkspaceName)
  }

  // One step around the app's windows from wherever the focus is.
  function stepWindow(windows, direction) {
    return DockModel.stepWindow(windows, direction, root.activeWindowAddress)
  }

  // Handles of this app's parked windows, in window order. Nothing is
  // remembered for this: the workspace a window sits on is the answer, so a
  // shell restart cannot lose track of one.
  function parkedWindows(windows) {
    return DockModel.windowsByParkedState(windows, root.isWinParkedLive, true)
  }

  // The app's parked window that has been waiting the longest — the head of
  // the chronological FIFO. Windows parked before this shell session have no
  // timestamp and sort first, matching the "recover the oldest" expectation.
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

  // The one window this app should put away: the focused one, else the one it
  // was last focused in, else the first that is still on screen.
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

  function minimizeApp(entry) {
    return root.minimizeMode === "all"
      ? root.minimizeAllWindows(entry)
      : root.minimizeOneWindow(entry)
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

    // recentOpenedWindowAddrs entries carry their own expiry; drop the stale ones.
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

  // Clears urgency entries from urgentMap for an application and its windows.
  // Called whenever an app/window receives focus or is activated/clicked by user.
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

    for (var t = 0; t < targetEntries.length; t++) {
      var tEntry = targetEntries[t]
      var tId = tEntry.appId || tEntry.id
      if (tId && map[tId]) { delete map[tId]; changed = true }
      if (tEntry.id && map[tEntry.id]) { delete map[tEntry.id]; changed = true }
      if (tEntry.appId && map[tEntry.appId]) { delete map[tEntry.appId]; changed = true }
      var tWins = tEntry.windowList || []
      for (var tw = 0; tw < tWins.length; tw++) {
        var twAddr = tWins[tw] ? tWins[tw].address : ""
        if (twAddr && map[twAddr]) {
          delete map[twAddr]
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

  // byValue: the map holds addresses as values (app -> window) rather than keys.
  function keepLive(map, live, byValue) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (live[byValue ? map[key] : key]) next[key] = map[key]
      else dropped = true
    }
    return dropped ? next : map
  }

  // Bindable from keybindings.lua, e.g.
  //   exec(mod, "M", "[Window Management] minimize to dock",
  //        "quickshell ipc call dock minimizeActive")
  IpcHandler {
    target: "dock"

    function minimizeActive(): void {
      var addr = root.activeWindowAddress
      if (addr !== "") root.minimizeToplevel(addr)
    }

    function transparency(): void { root.setTransparent(!root.transparent) }
    function blur(): void { root.setBlur(!root.blurred) }
    function link(): void { root.setLinkToBar(!root.linkToBar) }
    function position(edge: string): void {
      if (["top", "bottom", "left", "right"].indexOf(edge) >= 0) root.setDockEdge(edge)
    }

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
    var deskEntry = DockModel.entryFor(root.appRows, appId)
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

  // A pending launch ends when the app gained a window, or when waiting stops
  // being informative.
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
    conf.hoverEffect = root.hoverEffect
    delete conf.magnification
    conf.launchBounce = root.launchBounce
    conf.advancedTooltips = root.advancedTooltips
    if (root.screenName) conf.screen = root.screenName
    if (root.configuredIconSize > 0) conf.iconSize = root.configuredIconSize
    else delete conf.iconSize
    conf.opacity = root.dockOpacity < 0 ? "theme" : root.dockOpacity
    conf.shape = root.dockShape
    conf.bgColor = root.dockBgColor
    conf.folderColor = root.folderColor
    conf.linkToBar = root.linkToBar
    conf.edge = root.dockEdge
    conf.transparent = root.dockTransparent
    conf.blur = root.dockBlur
    conf.itemSpacing = root.itemSpacing
    conf.minimizeMode = root.minimizeMode
    conf.clickToMinimize = root.minimizeMode !== "off"
    conf.showUrgentHint = root.showUrgentHint
    conf.urgentSound = root.urgentSound
    conf.urgentSoundName = root.urgentSoundName
    conf.revealDelay = root.revealDelay
    conf.tooltipDelay = root.tooltipDelay
    conf.pinnedFolders = root.pinnedFolders
    configFile.setText(JSON.stringify(conf, null, 2))
  }

  // A left click says "give me this app". Everything below is decided from live
  // state only — which windows exist, which are parked, whether the focus is
  // already inside the app — so there is nothing to remember and nothing to go
  // stale:
  //
  //   no windows                      launch it
  //   focus elsewhere, something parked   bring the parked one back
  //   focus elsewhere                  focus it, preferring this workspace
  //   focus inside, mode "all"         park the whole app
  //   focus inside, several open       step to the app's next window
  //   focus inside, one open           park it, when parking is on
  //
  // Two of those rules carry the weight. Preferring a window on the current
  // workspace keeps a click from teleporting you while the app is already in
  // front of you. Stepping through windows is what makes every click on a
  // multi-window app do something visible: parking one of several hands focus
  // straight to a sibling, so the app never stops being active, and both a
  // park-first and a restore-first rule end up stuck — one parks forever, the
  // other toggles one window forever. Stepping has no such corner, and a
  // specific window can still be parked from the context menu.
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


    var hadUrgency = false
    var urgentWin = null
    for (var u = 0; u < visible.length; u++) {
      var ua = visible[u] ? visible[u].address : ""
      if (ua && root.urgentMap[ua]) {
        urgentWin = visible[u]
        hadUrgency = true
        break
      }
    }

    var urgentParked = null
    for (var p = 0; p < parked.length; p++) {
      var pa = parked[p] ? parked[p].address : ""
      if (pa && root.urgentMap[pa]) {
        urgentParked = parked[p]
        hadUrgency = true
        break
      }
    }

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

    // (preferring current workspace, then recent, then first). Restoring
    // minimized windows is the preview tiles' job — icon clicks never do it.
    if (visible.length > 0) {
      var target = root.windowHere(visible) || root.recentWindow(appId, visible) || visible[0]
      if (target && target.address) root.focusWindowByAddress(target.address, appId)
    }

    // All windows parked (or none): intentionally nothing. The dock's preview
    // tiles are the restore surface; a plain click must not surprise anyone.
  }

  // Menu rows name the workspace a window sits on, including the parked ones.
  // Which window the menu is pointed at, if the wheel or a hover put it there.
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
    return null
  }

  function setPinned(next) {
    root.pinnedIds = next
    dockFile.setText(DockModel.serializePinned(next))
  }

  function togglePin(appId) {
    root.setPinned(DockModel.togglePinned(root.pinnedIds, appId))
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
    if (!root.contextAppId || root.contextAppId === "__dock_settings__" || root.contextAppId === "__folder_context__") return
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
            appId: root.contextAppId,
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

  function openContext(appId, x, y) {
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
    root.contextDesktopActions = (deskEntry && deskEntry.actions) ? deskEntry.actions : []
    try { contextMenu.selectedWindowIdx = -1 } catch (e) {}
    root.contextAnchor = x
    root.contextY = y
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
    root.contextY = 0
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

  function openFolderContext(path, name, cx, cy) {
    root.closeFolderStack()
    root.contextFolderPath = path
    root.contextFolderName = name || "Folder"
    root.contextAnchor = cx
    root.contextY = cy
    root.contextAppId = "__folder_context__"
    root.syncVisibility()
  }

  function isFolderPinned(path) {
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var p = (list[i].path || "").replace(/^~/, Quickshell.env("HOME"))
      if (p === norm) return true
    }
    return false
  }

  function toggleFolderPin(path, name, icon) {
    var next = []
    var found = false
    var norm = (path || "").replace(/^~/, Quickshell.env("HOME"))
    var list = root.pinnedFolders || []
    for (var i = 0; i < list.length; i++) {
      var f = list[i]
      var p = (f.path || "").replace(/^~/, Quickshell.env("HOME"))
      if (p === norm) {
        found = true
      } else {
        next.push(f)
      }
    }
    if (!found) {
      next.push({ path: path, name: name || "Folder", icon: icon || DockModel.folderIconFor(path, "") })
    }
    root.pinnedFolders = next
    root.saveConfig()
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
    return Math.min(Math.max(widest, 220), Style.space(280))
  }


  // Back to a low threshold now that nothing paints outside the card: it only
  // has to clear the empty room the panel reserves for its popups, so even the
  // faintest opacity preset still gets its blur.
  Shell.LayerBlur { surface: "hypr-shell-dock"; enabled: root.blurred; ignoreAlpha: 0.1 }

  PanelWindow {
    id: dockWindow

    screen: root.dockScreen
    color: "transparent"
    WlrLayershell.namespace: "hypr-shell-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: (!root.autohide) ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: (!root.autohide)
      ? Math.round((root.vertical ? dockCard.width : dockCard.height) + Style.gapsOut * 2)
      : 0

    // The panel spans the dock's edge and reaches well into the screen, so
    // tooltips, menus and popovers have room to open away from that edge.
    anchors {
      top: root.edge !== "bottom"
      bottom: root.edge !== "top"
      left: root.edge !== "right"
      right: root.edge !== "left"
    }
    implicitWidth: 650
    implicitHeight: 650

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
        Region { item: revealStrip },
        Region { item: globalDismiss }
      ]
    }

    // Screen-edge reveal strip — thin edge trigger with zero click-swallowing
    Item {
      id: revealStrip
      // Spelled out rather than anchored per edge: assigning undefined to the
      // anchors that do not apply does not reliably unset them, and a strip
      // left stretched across the panel reports the whole dock as an edge
      // trigger, which keeps the dock up wherever the pointer is.
      width: root.vertical ? root.revealHeight : parent.width
      height: root.vertical ? parent.height : root.revealHeight
      x: root.edge === "right" ? parent.width - width : 0
      y: root.edge === "bottom" ? parent.height - height : 0

      HoverHandler {
        id: revealHover
        onHoveredChanged: root.syncVisibility()
      }

      // The grab handle sits on the screen edge and grows along the dock's axis.
      Rectangle {
        x: root.vertical
          ? (root.edge === "left" ? 0 : parent.width - width)
          : (parent.width - width) / 2
        y: root.vertical
          ? (parent.height - height) / 2
          : (root.edge === "top" ? 0 : parent.height - height)
        width: root.vertical ? Style.space(3) : (revealHover.hovered ? Style.space(48) : Style.space(24))
        height: root.vertical ? (revealHover.hovered ? Style.space(48) : Style.space(24)) : Style.space(3)
        radius: Math.min(width, height) / 2
        color: Util.alpha(Color.bar.text, revealHover.hovered ? 0.6 : 0.25)
        Behavior on width { NumberAnimation { duration: 150 } }
        Behavior on height { NumberAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
      }
    }

    // The bar's start popup anchors to the bar, so on a dock sitting opposite it
    // the menu would open across the screen from the button that spawned it.
    // The dock hosts its own under a separate name, positioned off its own edge,
    // and loads it only once it has actually been opened.
    Loader {
      id: startPopupLoader
      property bool everOpened: false
      active: startPopupLoader.everOpened
      visible: false
      sourceComponent: Component {
        Shell.StartPopup {
          anchorItem: appsButton
          shell: root.shell
          popupName: root.startPopupName
          position: root.edge
        }
      }
      Connections {
        target: root.shell
        function onPopupNameChanged() {
          if (root.shell.popupName === root.startPopupName) startPopupLoader.everOpened = true
        }
      }
    }

    Item {
      id: globalDismiss
      width: (root.contextAppId !== "" || root.activeStackFolder !== "") ? dockWindow.width : 0
      height: (root.contextAppId !== "" || root.activeStackFolder !== "") ? dockWindow.height : 0
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
        }
        onReleased: function(mouse) {
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.syncVisibility()
          }
        }
      }
    }


    // Upstream sat the card on a blurred black drop shadow. Its inner rectangle
    // covered the card exactly, so it darkened the glass from behind — the card
    // read far more solid than its own opacity — and it reached 24px past every
    // edge, which is the region Hyprland was blurring outside the dock.

    BorderSurface {
      id: dockCard

      readonly property color effectiveBgColor: {
        if (root.dockBgColor === "none") return Qt.rgba(0, 0, 0, 0.25)
        if (root.dockBgColor === "theme" || !root.dockBgColor) return Color.bar.background
        return root.dockBgColor
      }

      color: root.transparent
        ? "transparent"
        : (root.dockBgColor === "none" ? effectiveBgColor : Util.alpha(effectiveBgColor, root.effectiveDockOpacity))
      borderSpec: Border.none()
      radius: root.cardRadius(height)
      padding: Style.space(5)
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
        : -((root.vertical ? dockCard.width : dockCard.height) + Style.gapsOut + 10)
      property real slideOffset: dockCard.edgeOffset
      Behavior on slideOffset { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

      x: root.vertical
        ? (root.edge === "left" ? slideOffset : parent.width - width - slideOffset)
        : (parent.width - width) / 2
      y: root.vertical
        ? (parent.height - height) / 2
        : (root.edge === "top" ? slideOffset : parent.height - height - slideOffset)

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
          if (root.dragAppId !== "") {
            root.dragAppId = ""
            root.dropBeforeId = ""
            root.syncVisibility()
          }
        }
      }

      // A Grid rather than a Row so the spine can flip axis from a binding:
      // rows 1 lays the children out horizontally, columns 1 vertically.
      Grid {
        id: row
        z: 1
        spacing: Style.space(root.itemSpacing)
        // Only columns is set: Grid then derives its own row count, which is
        // what keeps the spine a single line on either axis. Setting rows too
        // makes Grid reserve the full rows x columns block and warn whenever
        // the pair momentarily fails to cover the children.
        columns: root.vertical ? 1 : Math.max(1, row.visibleChildren.length)

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
          card: dockCard
          id: appsButton
          visible: root.showAppsButton
          homeCenter: root.slotHomeCenter(0, 0, false)
          glyph: root.shell ? root.shell.distroGlyph : ""
          glyphColor: root.dockForeground
          tooltip: "Applications"
          onPressed: { if (root.shell) root.shell.togglePopup(root.startPopupName) }
          onMiddleClicked: { if (root.shell) root.shell.run([root.shell.terminal]) }
          onWheelScrolled: function(dir) { root.cycleWorkspace(dir) }
          onMenuRequested: function(cx, cy) {
            root.openDockSettingsMenu(cx, cy)
          }
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
            homeCenter: root.slotHomeCenter(root.appsSlots + root.appsSeparatorCount + index,
                                            root.appsSlots + index, root.appsSeparatorCount)
            pinned: true
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx, cy) { root.openContext(aid, cx, cy) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }
            onDragStarted: function(aid) {
              root.dragAppId = aid
              root.dropBeforeId = ""
            }
            onDragMoved: function(aid, mx) {
              root.dropBeforeId = ""
              var count = pinnedRepeater.count
              var found = false
              for (var i = 0; i < count; i++) {
                var child = pinnedRepeater.itemAt(i)
                if (!child || !child.visible) continue
                var childGlobalX = row.x + child.x
                var childCenter = childGlobalX + child.width / 2
                if (mx < childCenter) {
                  root.dropBeforeId = child.appId
                  root.dropIndicatorX = childGlobalX - Style.space(1)
                  found = true
                  break
                }
              }
              if (!found && count > 0) {
                for (var j = count - 1; j >= 0; j--) {
                  var lastChild = pinnedRepeater.itemAt(j)
                  if (lastChild && lastChild.visible) {
                    root.dropBeforeId = ""
                    root.dropIndicatorX = row.x + lastChild.x + lastChild.width + Style.space(1)
                    break
                  }
                }
              }
            }
            onDragDropped: function(aid) {
              var dragId = root.dragAppId
              var beforeId = root.dropBeforeId
              root.dragAppId = ""
              root.dropBeforeId = ""
              if (dragId !== "") {
                root.setPinned(DockModel.reorderPinned(root.pinnedIds, dragId, beforeId))
              }
              root.syncVisibility()
            }
          }
        }

        DockSeparator { dock: root; visible: root.hasLeftTileSeparator }

        // macOS-style section: every parked window shows up as a small live
        // preview tile. Click a tile to bring that exact window back.
        Repeater {
          id: minimizedTilesRepeater
          model: root.tileModel

          delegate: Item {
            id: tile
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
            readonly property real homeCenter: root.slotHomeCenter(
              root.appsSlots + root.appsSeparatorCount + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + index,
              root.appsSlots + root.pinnedSection.length + index,
              root.appsSeparatorCount,
              (root.hasLeftTileSeparator ? root.separatorWidth : 0) + index * root.tileMainSize + (root.tileMainSize - root.iconSlot) / 2)
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

            function doClose() {
              for (var i = 0; i < groupWins.length; i++) {
                var w = groupWins[i]
                if (w && w.address) root.hyprDispatch(
                  'hl.dsp.window.close({ window = "address:' + w.address + '" })',
                  "closewindow address:" + w.address)
              }
            }

            readonly property real tileMain: root.tileMainSize * (root.waveHover ? tile.magnifyScale : 1)
            // A tile is shorter than a slot across the dock and used to anchor
            // itself centred, which a Grid child may not do. The delegate now
            // fills the slot on the cross axis and centres the tile within it.
            width: root.vertical ? root.iconSlot : tile.tileMain
            height: root.vertical ? tile.tileMain : root.iconSlot
            opacity: root.dockVisible ? 1 : 0

            // Zoom mode scales this visual stack in place (the preview overlaps
            // neighbors exactly like magnified app icons); wave mode grows the
            // tile itself, so the wrapper stays at scale 1 there.
            Item {
              id: tileVisual
              anchors.centerIn: parent
              width: root.vertical ? root.tileCrossSize : tile.tileMain
              height: root.vertical ? tile.tileMain : root.tileCrossSize
              scale: root.waveHover ? 1 : tile.magnifyScale

              // Stacked-card layers behind grouped tiles hint at the count.
              Rectangle {
                visible: tile.isGroup && tile.groupCount > 1
                anchors.fill: parent
                anchors.leftMargin: -Style.space(3)
                anchors.bottomMargin: -Style.space(2)
                radius: root.tileRadius
                color: Util.alpha(root.dockForeground, 0.16)
                border.width: 1
                border.color: Util.alpha(root.dockForeground, 0.38)
              }
              Rectangle {
                visible: tile.isGroup && tile.groupCount > 2
                anchors.fill: parent
                anchors.leftMargin: -Style.space(6)
                anchors.bottomMargin: -Style.space(4)
                radius: root.tileRadius
                color: Util.alpha(root.dockForeground, 0.11)
                border.width: 1
                border.color: Util.alpha(root.dockForeground, 0.28)
              }

              Rectangle {
                anchors.fill: parent
                radius: root.tileRadius
                color: tileArea.containsMouse ? Color.menu.selectedBackground : Util.alpha(root.dockForeground, 0.10)
                border.width: 1
                border.color: Util.alpha(root.dockForeground, tileArea.containsMouse ? 0.55 : 0.22)
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
                function requestFrame() {
                  if (hasContent || !captureSource) return
                  captureRetry.attempts = 0
                  captureRetry.restart()
                }
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
                  repeat: attempts < 6
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

              // App-icon badge: only shown when there's no preview yet (letter)
              // or when the group has 2+ windows (count). Single-window tiles
              // never show a "1" badge once the preview has loaded.
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

            // Title bubble above the hovered tile (hidden while the menu is open).
            BorderSurface {
              id: tileTooltip
              visible: tile.tileHovered && !tile.tileMenuOpen && tile.tileTitle !== ""
              z: 300
              color: Util.alpha(Color.tooltip.background, root.dockSurfaceOpacity)
              borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
              padding: Style.space(4)
              x: root.tipX(parent.width, width, Style.space(6))
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
                  var max = Math.min(tile.groupWins.length, 6)
                  for (var i = 0; i < max; i++) lines.push("• " + (tile.groupWins[i] ? tile.groupWins[i].title : ""))
                  if (tile.groupWins.length > 6) lines.push("+" + (tile.groupWins.length - 6) + " more")
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
                if (!tile.win || !tile.win.address) return
                if (mouse.button === Qt.RightButton) {
                  var pt = tile.mapToItem(dockCard, tile.width / 2, 0)
                  var gx = dockCard.x + (pt ? pt.x : (tile.x + tile.width / 2))
                  root.openTileContext(tile.groupWins, tile.win.appId || "", gx)
                } else if (root.contextAppId === "__tile_context__") {
                  root.closeContext()
                } else {
                  tile.doRestore()
                }
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
            readonly property int visibleIdx: root.visibleRunningSlotBefore(index)
            homeCenter: root.slotHomeCenter(
              root.appsSlots + root.appsSeparatorCount + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + visibleIdx,
              root.appsSlots + root.pinnedSection.length + visibleIdx,
              root.appsSeparatorCount + (root.hasSeparator ? 1 : 0),
              root.tilesFixedWidth)
            pinned: false
            active: modelData.appId === root.activeId
            onActivateRequested: function(aid) { root.activate(aid) }
            onNewWindowRequested: function(aid) { root.launchApp(aid, null) }
            onMenuRequested: function(aid, cx, cy) { root.openContext(aid, cx, cy) }
            onWheelScrolled: function(aid, dir) { root.cycleApp(aid, dir) }

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
            dockContent: dockWindow.contentItem
            folderPath: modelData.path
            name: modelData.name || "Folder"
            icon: modelData.icon || DockModel.folderIconFor(modelData.path, "")
            homeCenter: root.slotHomeCenter(
              root.appsSlots + root.appsSeparatorCount + root.pinnedSection.length + (root.hasLeftTileSeparator ? 1 : 0) + (root.hasSeparator ? 1 : 0) + root.tileElements + root.visibleRunningCount + (root.hasFolderSeparator ? 1 : 0) + index,
              root.appsSlots + root.pinnedSection.length + root.visibleRunningCount + index,
              root.appsSeparatorCount + (root.hasSeparator ? 1 : 0) + (root.hasFolderSeparator ? 1 : 0),
              root.tilesFixedWidth)
            onOpenStackRequested: function(fpath, fname, cx, cy) {
              root.openFolderStack(fpath, fname, cx)
            }
            onMenuRequested: function(fpath, fname, cx, cy) {
              root.openFolderContext(fpath, fname, cx, cy)
            }
          }
        }
      }

      Rectangle {
        visible: root.dragAppId !== ""
        x: root.dropIndicatorX
        anchors.verticalCenter: row.verticalCenter
        width: Style.space(2)
        height: root.iconSize + Style.space(4)
        radius: 1
        color: Color.bar.active
        z: 10
      }
    }

    BorderSurface {
      id: folderStackPopover
      visible: root.activeStackFolder !== "" && root.dockVisible
      opacity: (root.activeStackFolder !== "" && root.dockVisible) ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      z: 100
      color: Util.alpha(Color.menu.background, root.dockSurfaceOpacity)
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

      x: root.vertical ? root.panelCross(width) : root.panelMain(width, root.activeStackAnchor)
      y: root.vertical ? root.panelMain(height, root.activeStackAnchor) : root.panelCross(height)

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
      }
    }
    DockContextMenu {
      id: contextMenu
      dock: root
    }
  }
}

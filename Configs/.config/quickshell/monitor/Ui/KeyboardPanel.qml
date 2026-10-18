import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons

PopupWindow {
  id: root
  required property Item anchorItem
  required property var shell
  property var owner: null
  property int margin: Commons.Style.gapsOut
  property int padding: Commons.Style.spacing.panelPadding
  property int contentWidth: Commons.Style.space(430)
  property int contentHeight: Commons.Style.space(500)
  property var borderSpec: Commons.Border.surfaceSpec("popups", "border", Commons.Style.popupBorder(Commons.Color.popups.border), Math.max(1, Commons.Style.space(1)))
  property bool centerOnBar: false
  property bool open: false
  property Item focusTarget: null
  default property alias panelContent: contentHolder.data
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property bool centered: shell && owner
    && shell.popupCenteredName === owner.popupName

  function close() {
    if (owner && "close" in owner) owner.close()
    else open = false
  }
  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var available = anchorWindow && anchorWindow.screen ? anchorWindow.screen.width - margin * 2 : desired
    if (cap !== undefined && Number(cap) > 0) available = Math.min(available, Number(cap))
    return Math.round(Math.min(desired, available))
  }
  function fittedContentHeight(height, cap) {
    var desired = Math.max(1, Number(height) || 1) + padding * 2 + Commons.Border.top(borderSpec) + Commons.Border.bottom(borderSpec)
    var available = anchorWindow && anchorWindow.screen ? anchorWindow.screen.height - margin * 2 : desired
    if (cap !== undefined && Number(cap) > 0) available = Math.min(available, Number(cap))
    return Math.round(Math.min(desired, available))
  }

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight
  function focusContent() {
    if (open && backingWindowVisible && focusTarget) focusTarget.forceActiveFocus()
  }
  onOpenChanged: focusContent()
  onBackingWindowVisibleChanged: focusContent()

  HyprlandFocusGrab {
    active: root.open && root.backingWindowVisible && !(root.shell && root.shell.focusPriming)
    windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
    onCleared: if (root.open) root.close()
  }

  anchor {
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1
    onAnchoring: {
      if (!root.anchorItem || !root.anchorWindow) return
      if (root.centered) {
        var screen = root.anchorWindow.screen
        if (!screen) return
        var windowAnchors = root.anchorWindow.anchors
        var originX = windowAnchors.left ? 0 : windowAnchors.right
          ? screen.width - root.anchorWindow.width : (screen.width - root.anchorWindow.width) / 2
        var originY = windowAnchors.top ? 0 : windowAnchors.bottom
          ? screen.height - root.anchorWindow.height : (screen.height - root.anchorWindow.height) / 2
        anchor.rect.x = Math.round((screen.width - root.width) / 2 - originX)
        anchor.rect.y = Math.round((screen.height - root.height) / 2 - originY)
        return
      }
      var x = root.anchorItem.width / 2 - root.width / 2
      var y = root.anchorItem.height + root.margin
      var edge = root.shell && root.shell.barEdge ? root.shell.barEdge : "top"
      if (edge === "bottom") y = -root.height - root.margin
      else if (edge === "left") { x = root.anchorItem.width + root.margin; y = root.anchorItem.height / 2 - root.height / 2 }
      var point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, y)
      anchor.rect.x = Math.round(point.x)
      anchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    opacity: root.open ? 1 : 0
    color: Commons.Color.alpha(Commons.Style.popupTinted(Commons.Color.popups.background), Commons.Style.popupSurfaceOpacity)
    borderSpec: root.borderSpec
    radius: Commons.Style.cornerRadius
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    FocusScope {
      anchors.fill: parent
      anchors.topMargin: root.padding + card.borderTop
      anchors.rightMargin: root.padding + card.borderRight
      anchors.bottomMargin: root.padding + card.borderBottom
      anchors.leftMargin: root.padding + card.borderLeft
      focus: root.open
      Item { id: contentHolder; anchors.fill: parent }
    }
  }
}

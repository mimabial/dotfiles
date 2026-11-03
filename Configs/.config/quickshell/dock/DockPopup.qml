import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
  id: popup
  required property var dock
  required property PanelWindow host
  required property Item body
  required property bool open
  required property real anchorX
  default property alias content: keyCatcher.data

  readonly property bool below: popup.dock.edge === "top"

  visible: popup.open
  color: "transparent"
  implicitWidth: popup.host.width
  implicitHeight: popup.host.screen ? popup.host.screen.height : popup.host.height
  mask: Region { item: popup.body }

  anchor.window: popup.host
  anchor.rect.width: popup.host.width
  anchor.rect.height: popup.host.height
  anchor.edges: (popup.below ? Edges.Top : Edges.Bottom) | Edges.Left
  anchor.gravity: (popup.below ? Edges.Bottom : Edges.Top) | Edges.Right
  anchor.adjustment: PopupAdjustment.None

  Binding {
    target: popup.body
    property: "x"
    value: popup.dock.panelX(popup.body.width, popup.anchorX)
  }
  Binding {
    target: popup.body
    property: "y"
    value: popup.dock.panelY(popup.body.height) + (popup.below ? 0 : popup.implicitHeight - popup.host.height)
  }

  FocusScope {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.onPressed: event => event.accepted = popup.dock.handleMenuKey(event)
  }

  HyprlandFocusGrab {
    active: popup.backingWindowVisible && !popup.dock.menuFocusPriming
    windows: [popup, popup.host]
    onCleared: if (popup.open) popup.dock.closePanels()
  }
}

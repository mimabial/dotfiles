import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
  id: surface

  required property var controller
  readonly property alias view: fieldView
  property real fadeOpacity: controller && controller.opened && controller.revealed ? 1 : 0

  visible: controller !== null && (controller.opened || surface.fadeOpacity > 0)
  screen: controller ? controller.targetScreen : null
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  HyprlandWindow.opacity: surface.fadeOpacity
  mask: controller && controller.opened ? null : emptyInput
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "switcher"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: controller && controller.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  onVisibleChanged: {
    if (visible) Qt.callLater(fieldView.focusKeys)
    else if (surface.controller) surface.controller.clearField()
  }

  Behavior on fadeOpacity {
    NumberAnimation { duration: fieldView.appearance.fadeDuration; easing.type: Easing.InOutCubic }
  }

  Region { id: emptyInput }

  Connections {
    target: surface.visible ? fieldView.Window.window : null
    function onFrameSwapped() {
      if (surface.controller.opened && !surface.controller.revealed)
        surface.controller.revealed = true
    }
  }

  FieldView {
    id: fieldView

    anchors.fill: parent
    enabled: surface.controller !== null && surface.controller.opened
    controller: surface.controller
  }
}

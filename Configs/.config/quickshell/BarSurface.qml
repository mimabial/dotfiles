import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var shell
    property bool active: false
    readonly property bool popupsAllowed: active && (!Hyprland.focusedMonitor
        || !screen || Hyprland.focusedMonitor.name === screen.name)
    readonly property bool popupOpen: shell.popupName !== "" && popupsAllowed
    readonly property string focusRequest: popupOpen
        ? shell.popupName + (shell.popupCard && shell.popupCard.wantsKeyboard ? ":input" : "") : ""
    property bool acquiringKeyboardFocus: false
    function finishFocusAcquisition() {
        if (!acquiringKeyboardFocus || !keyboardRouter.Window.active) return
        acquiringKeyboardFocus = false
        shell.focusPriming = false
    }
    function floatMargin(edge) {
        const inner = ({ top: "bottom", bottom: "top" })[shell.barEdge]
        return shell.prefs.barFloating && edge !== inner ? shell.barFloatGap : 0
    }

    visible: active
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: active ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: !popupOpen ? WlrKeyboardFocus.None
        : acquiringKeyboardFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    HoverHandler {
        onHoveredChanged: if (root.shell.mode === "winbar" && root.shell.prefs.winbarAutoHide) root.shell.barRevealed = hovered
    }

    Rectangle {
        id: surface
        readonly property var box: root.shell.style.box("bar." + root.shell.barEdge)
        anchors.fill: parent; color: root.shell.barColor; radius: root.shell.prefs.barFloating ? root.shell.rounding : 0
        SideBorder { shell: root.shell; host: surface }
    }

    onFocusRequestChanged: {
        acquiringKeyboardFocus = focusRequest !== ""
        shell.focusPriming = acquiringKeyboardFocus
        finishFocusAcquisition()
    }

    Item {
        id: keyboardRouter
        anchors.fill: parent
        focus: true
        Window.onActiveChanged: root.finishFocusAcquisition()
        Keys.onPressed: event => {
            if (root.shell.popupCard) event.accepted = root.shell.popupCard.handleKey(event)
        }
    }
}

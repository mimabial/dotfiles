import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var shell
    property bool active: false
    // Concurrent per-monitor popup grabs cancel, so only the focused one owns them.
    readonly property bool popupsAllowed: active && (!Hyprland.focusedMonitor
        || !screen || Hyprland.focusedMonitor.name === screen.name)
    readonly property bool popupOpen: shell.popupName !== "" && popupsAllowed
    readonly property bool popupNeedsFocus: popupOpen && (shell.popupCenteredName === shell.popupName
        || shell.popupCard && shell.popupCard.wantsKeyboard)
    property bool exclusivePhase: false

    color: shell.barColor
    exclusionMode: active ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-bar"
    WlrLayershell.layer: WlrLayer.Top
    // Prime focus briefly; holding Exclusive would swallow outside clicks.
    WlrLayershell.keyboardFocus: !popupOpen ? WlrKeyboardFocus.None
        : exclusivePhase ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    onPopupNeedsFocusChanged: {
        exclusivePhase = popupNeedsFocus
        shell.focusPriming = popupNeedsFocus
        if (popupNeedsFocus) focusPrime.restart()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (root.shell.popupCard) event.accepted = root.shell.popupCard.handleKey(event)
        }
    }
    Timer {
        id: focusPrime
        interval: 150
        onTriggered: {
            root.exclusivePhase = false
            root.shell.focusPriming = false
        }
    }
}

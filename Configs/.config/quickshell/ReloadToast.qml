import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var shell
    property bool shown: false
    property bool failed: false

    function show(error) { failed = error; shown = true; hide.restart() }
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); root.show(false) }
        function onReloadFailed(error: string) { Quickshell.inhibitReloadPopup(); root.show(true) }
    }
    Timer { id: hide; interval: root.failed ? 5000 : 1400; onTriggered: root.shown = false }

    PanelWindow {
        visible: root.shown
        anchors.top: root.shell.mode !== "top"; anchors.bottom: root.shell.mode === "top"
        margins.top: Style.xxxl; margins.bottom: Style.xxxl
        implicitWidth: message.implicitWidth + Style.xxl * 2; implicitHeight: 34
        color: "transparent"; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hypr-shell-reload"; WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent; radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .96)
            border.width: 1; border.color: root.shell.alpha(root.shell.role(root.failed ? "error" : "act_br", root.shell.accent), .65)
            Text {
                id: message; anchors.centerIn: parent
                text: root.failed ? "Configuration reload failed" : "Configuration reloaded"
                color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            MouseArea { anchors.fill: parent; onClicked: root.shown = false }
        }
    }
}

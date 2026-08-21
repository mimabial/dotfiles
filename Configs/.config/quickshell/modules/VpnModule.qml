import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-vpn"
    command: ["hyprshell", "waybar.vpn.sh"]; interval: 5000
    readonly property string state: String(output.class || "")
    textColor: state === "connected" ? root.shell.role("c2", root.shell.foreground)
        : state === "error" ? root.shell.role("error", root.shell.foreground)
        : state === "connecting" ? root.shell.alpha(root.shell.role("accent", root.shell.foreground), .4 + vpnBlink.phase * .5)
        : root.shell.role("c1", root.shell.foreground)
    SequentialAnimation {
        id: vpnBlink
        property real phase: 0
        running: root.state === "connecting"; loops: Animation.Infinite
        onStopped: phase = 0
        NumberAnimation { target: vpnBlink; property: "phase"; from: 0; to: 1; duration: 750 }
        NumberAnimation { target: vpnBlink; property: "phase"; from: 1; to: 0; duration: 750 }
    }
    // left opens the panel, right toggles the tunnel
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "waybar.vpn.toggle.sh"])
        : root.shell.togglePopup("vpn")
    VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

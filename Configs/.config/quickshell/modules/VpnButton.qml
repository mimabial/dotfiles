import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "vpn"
    command: ["hyprshell", "waybar.vpn.sh"]; interval: 5000
    // left opens the panel, right toggles the tunnel
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "waybar.vpn.toggle.sh"])
        : root.shell.togglePopup("vpn")
    VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

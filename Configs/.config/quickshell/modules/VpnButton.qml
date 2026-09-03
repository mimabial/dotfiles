import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "vpn"
    command: ["hyprshell", "quickshell/vpn"]; interval: 5000
    // left opens the panel, right toggles the tunnel
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "quickshell/vpn-toggle"])
        : root.shell.togglePopup("vpn")
    VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

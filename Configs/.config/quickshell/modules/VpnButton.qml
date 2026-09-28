import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    property string popupName: "vpn"
    css: "vpn"
    command: [shell.home + "/.local/lib/hypr/quickshell/vpn.sh"]; interval: 5000
    // left opens the panel, right toggles the tunnel
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "quickshell/vpn-toggle"])
        : root.shell.togglePopup(root.popupName)
    VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

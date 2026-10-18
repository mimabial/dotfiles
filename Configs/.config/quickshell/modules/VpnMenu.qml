import QtQuick
import ".."

VpnButton {
    id: root
    popupName: "vpn-menu"
    settingsPopupName: popupName + "-settings"
    symbol: String(output.class) === "connected" ? "network-vpn" : "network-vpn-disconnected"
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: root.popupName; settings: "VPN"; settingsPopup: root.settingsPopupName
        PopupToggleRow {
            width: parent.width; shell: root.shell; title: "VPN"; checked: String(root.output.class) === "connected"
            detail: String(root.output.tooltip || "").replace(/<[^>]+>/g, "").split("\n").slice(1).join(" · ")
            onToggled: root.shell.run(["hyprshell", "quickshell/vpn-toggle"], root.refresh)
        }
    }
}

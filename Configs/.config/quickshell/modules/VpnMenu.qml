import QtQuick
import ".."

VpnButton {
    id: root
    popupName: "vpn-menu"
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "vpn-menu"; settings: "VPN"; settingsPopup: "vpn"
        PopupToggleRow {
            width: parent.width; shell: root.shell; title: "VPN"; checked: String(root.output.class) === "connected"
            detail: String(root.output.tooltip || "").replace(/<[^>]+>/g, "").split("\n").slice(1).join(" · ")
            onToggled: root.shell.run(["hyprshell", "quickshell/vpn-toggle"], root.refresh)
        }
    }
}

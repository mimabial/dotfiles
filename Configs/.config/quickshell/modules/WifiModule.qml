import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showReadout: false
    property bool showVpn: false
    css: "wifi"; reverse: true
    secondaryAvailable: root.showReadout || root.showVpn
    holdOpen: ["network", "wifiqr", "vpn"].includes(root.shell.popupName)
    primary: Component { BarButton {
        id: wifiButton
        shell: root.shell; css: "custom-wifimenu"; text: "󰖩"
        // omarchy: left opens the panel, right toggles the radio
        onClicked: button => button === Qt.RightButton
            ? Networking.wifiEnabled = !Networking.wifiEnabled
            : root.shell.togglePopup("network")
        NetworkPopup { anchorItem: wifiButton; shell: root.shell; popupEnabled: root.popupsAllowed }
        WifiQrPopup { anchorItem: wifiButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { ColumnLayout { spacing: 0
        VpnModule {
            Layout.fillWidth: true; visible: root.showVpn
            shell: root.shell; popupsAllowed: root.popupsAllowed
        }
        ScriptButton {
            id: speedButton
            Layout.fillWidth: true; visible: root.showReadout
            shell: root.shell; css: "custom-network.speed"
            command: ["hyprshell", "sysinfo/network-speed"]; interval: 3000
        }
    } }
}

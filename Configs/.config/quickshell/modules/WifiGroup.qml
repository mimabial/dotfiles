pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showReadout: false
    property bool showVpn: false
    property bool vpnFirst: false
    readonly property var network: {
        for (const device of Networking.devices.values)
            if (device.type === DeviceType.Wifi)
                for (const candidate of device.networks.values)
                    if (candidate.connected) return candidate
        return null
    }
    css: "wifi"; reverse: true
    secondaryAvailable: root.showReadout || root.showVpn
    holdOpen: ["network", "wifiqr", "vpn"].includes(root.shell.popupName)
    slots: (root.showVpn && root.vpnFirst ? [vpnSlot] : []).concat([wifiSlot])
        .concat(root.showReadout ? [speedSlot] : [])
        .concat(root.showVpn && !root.vpnFirst ? [vpnSlot] : [])

    Component { id: wifiSlot; BarButton {
        id: wifiButton
        shell: root.shell; css: "wifimenu"; text: "󰖩"
        tooltip: !Networking.wifiEnabled ? "Wi-Fi off"
        : !root.network ? "Not Connected to any type of Network"
        : root.network.name + "\nSignal: " + Math.round(root.network.signalStrength * 100) + "%"
        // omarchy: left opens the panel, right toggles the radio
        onClicked: button => button === Qt.RightButton
            ? Networking.wifiEnabled = !Networking.wifiEnabled
            : root.shell.togglePopup("network")
        NetworkPopup { anchorItem: wifiButton; shell: root.shell; popupEnabled: root.popupsAllowed }
        WifiQrPopup { anchorItem: wifiButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: vpnSlot; VpnButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: speedSlot; ScriptButton {
        shell: root.shell; css: "network.speed"; tooltip: ""
        command: ["hyprshell", "sysinfo/network-speed"]; interval: 3000
    } }
}

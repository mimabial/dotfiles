pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import ".."

WifiButton {
    id: root
    readonly property var networks: {
        const wifi = Array.from(Networking.devices.values).find(device => device.type === DeviceType.Wifi)
        return wifi ? Array.from(wifi.networks.values).filter(network => network.name)
            .sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength).slice(0, 8) : []
    }
    popupName: "wifi-menu"
    symbol: !Networking.wifiEnabled ? "network-wireless-disabled" : !connectedNetwork ? "network-wireless-offline"
        : "network-wireless-signal-" + ["none", "weak", "ok", "good", "excellent"][Math.min(4, Math.floor(connectedNetwork.signalStrength * 5))]
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "wifi-menu"; settings: "Wi-Fi"; settingsPopup: "network"
        PopupToggleRow { width: parent.width; shell: root.shell; title: "Wi-Fi"; checked: Networking.wifiEnabled; onToggled: Networking.wifiEnabled = !Networking.wifiEnabled }
        Repeater {
            model: Networking.wifiEnabled ? root.networks : []
            PopupRow {
                required property var modelData
                readonly property bool open: modelData.security === WifiSecurityType.Open
                width: parent.width; shell: root.shell; title: modelData.name; value: open ? "" : "󰌾"
                icon: ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(modelData.signalStrength * 4))]
                iconColor: modelData.connected ? root.shell.accent : root.shell.alpha(root.shell.foreground, .55)
                onClicked: modelData.connected ? modelData.disconnect() : modelData.known || open ? modelData.connect() : root.shell.togglePopup("network")
            }
        }
    }
}

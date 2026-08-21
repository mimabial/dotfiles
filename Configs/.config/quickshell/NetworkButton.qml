import QtQuick
import Quickshell.Networking

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var network: {
        for (const device of Networking.devices.values)
            if (device.type === DeviceType.Wifi)
                for (const candidate of device.networks.values)
                    if (candidate.connected) return candidate
        return null
    }
    css: Networking.wifiEnabled ? "network.wifi" : "network.disabled"
    text: !Networking.wifiEnabled ? "󰖪" : "󰖩"
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "rofi/wifi"]) : shell.togglePopup("network")

    NetworkPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    WifiQrPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

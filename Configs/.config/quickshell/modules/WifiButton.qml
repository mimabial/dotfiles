pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var connectedNetwork: {
        for (const device of Networking.devices.values)
            if (device.type === DeviceType.Wifi)
                for (const candidate of device.networks.values)
                    if (candidate.connected) return candidate
        return null
    }
    css: "wifi"; text: "󰖩"
    tooltip: !Networking.wifiEnabled ? "Wi-Fi off"
        : !root.connectedNetwork ? "Not connected"
        : root.connectedNetwork.name + "\nSignal: " + Math.round(root.connectedNetwork.signalStrength * 100) + "%"
    onClicked: button => button === Qt.RightButton
        ? Networking.wifiEnabled = !Networking.wifiEnabled
        : root.shell.togglePopup("network")
    NetworkPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
    WifiQrPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

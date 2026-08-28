import QtQuick
import Quickshell.Bluetooth

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(device => device.connected)
    css: "bluetooth-button.connected"
    radius: shell.moduleRadius
    text: {
        const levels = connected.filter(device => device.batteryAvailable).map(device => Math.round(device.battery * 100))
        return "󰂱" + (levels.length ? " " + levels.join("/") : "")
    }
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "rofi/bluetooth"]) : shell.togglePopup("bluetooth")

    BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

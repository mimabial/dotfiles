import QtQuick
import Quickshell.Bluetooth

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: Bluetooth.devices.values.filter(device => device.connected)
    css: "custom-bluetooth.connected"
    radius: shell.moduleRadius
    fill: shell.alpha(shell.background, .1)
    outline: shell.alpha(shell.role("br", shell.foreground), .3)
    text: {
        const levels = connected.filter(device => device.batteryAvailable).map(device => Math.round(device.battery * 100))
        return "" + (levels.length ? " " + levels.join("/") : "")
    }
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "rofi/bluetooth"]) : shell.togglePopup("bluetooth")

    BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

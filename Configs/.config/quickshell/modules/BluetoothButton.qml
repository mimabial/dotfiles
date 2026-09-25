pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool showReadout: false
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var connected: Bluetooth.devices.values.filter(device => device.connected)
    readonly property string power: connected.length ? "connected" : adapters.some(adapter => adapter.enabled) ? "on" : "off"
    css: "bluetooth." + power
    text: ({ connected: "󰂱", on: "󰂯", off: "󰂲" })[power]
    badgeText: showReadout && connected.length ? countGlyph(connected.length) : ""
    // the tooltip renders as rich text, so the rows are separated by <br>
    tooltip: !adapters.length ? "No Bluetooth controller"
        : "<b>Connected</b>" + (connected.length ? "" : " none")
            + connected.map(device => "<br>" + (device.batteryAvailable
                ? device.name + " " + Math.round(device.battery * 100) + "%" : device.name)).join("")
    // Left opens the panel; right uses the same persistent power path.
    onClicked: button => {
        if (button !== Qt.RightButton) return shell.togglePopup("bluetooth")
        shell.run(["hyprshell", "bluetooth/power", "toggle"])
    }
    BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

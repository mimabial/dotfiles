pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showReadout: false
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var connected: Bluetooth.devices.values.filter(device => device.connected)
    css: "bluetooth"; reverse: true
    secondaryAvailable: root.showReadout
    holdOpen: root.shell.popupName === "bluetooth"
    primary: Component { BarButton {
        id: bluetoothButton
        shell: root.shell; css: "bluetooth-button"
        text: root.connected.length ? "<b>󰂱</b>" : root.adapters.some(adapter => adapter.enabled) ? "󰂯" : "󰂲"
        // the tooltip renders as rich text, so the rows are separated by <br>
        tooltip: !root.adapters.length ? "No Bluetooth controller"
            : "<b>Connected</b>" + (root.connected.length ? "" : " none")
                + root.connected.map(device => "<br>" + (device.batteryAvailable
                    ? device.name + " " + Math.round(device.battery * 100) + "%" : device.name)).join("")
        // Left opens the panel; right uses the same persistent power path.
        onClicked: button => {
            if (button !== Qt.RightButton) return root.shell.togglePopup("bluetooth")
            root.shell.run(["hyprshell", "bluetooth/power", "toggle"])
        }
        BluetoothPopup { anchorItem: bluetoothButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { BarButton {
        shell: root.shell; css: "bluetooth-button.status"
        readonly property var solo: root.connected.length === 1 && root.connected[0].batteryAvailable ? root.connected[0] : null
        text: solo ? "<small><b>" + Math.round(solo.battery * 100) + "</b></small>"
            : root.connected.length ? "<b>" + root.connected.length + "</b>" : ""
        visible: text !== ""
    } }
}

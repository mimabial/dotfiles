pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import ".."
import "../BluetoothModel.js" as Model

BarButton {
    id: root
    property bool popupEnabled: true
    property string popupName: "bluetooth"
    property string settingsPopupName: popupName
    property bool showBadge: false
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var connected: Bluetooth.devices.values.filter(device => device.connected)
    readonly property string power: connected.length ? "connected" : adapters.some(adapter => adapter.enabled) ? "on" : "off"
    readonly property var lowestBattery: connected.filter(device => device.batteryAvailable)
        .reduce((lowest, device) => !lowest || device.battery < lowest.battery ? device : lowest, null)
    readonly property string batteryAlert: lowestBattery ? Model.batteryAlert({percent: Math.round(lowestBattery.battery * 100)}) : ""
    css: "bluetooth." + (batteryAlert || power)
    text: batteryAlert ? Model.monitorKindIcon(Model.bluezKind(lowestBattery.icon)) : ({ connected: "󰂱", on: "󰂯", off: "󰂲" })[power]
    badgeText: showBadge && connected.length ? root.countText(connected.length) : ""
    tooltip: !adapters.length ? "No Bluetooth controller"
        : "<b>Connected</b>" + (connected.length ? "" : " none")
            + connected.map(device => "<br>" + (device.batteryAvailable
                ? device.name + " " + Math.round(device.battery * 100) + "%" : device.name)).join("")
    onClicked: button => {
        if (button !== Qt.RightButton) return shell.togglePopup(popupName)
        shell.run(["hyprshell", "bluetooth/power", "toggle"])
    }
    BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; popupName: root.settingsPopupName }
}

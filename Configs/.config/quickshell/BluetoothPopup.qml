import QtQuick
import Quickshell.Bluetooth

PopupCard {
    id: root
    popupName: "bluetooth"
    contentWidth: Style.px(380)
    contentHeight: Style.px(420)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
    readonly property var connected: devices.filter(device => device && device.connected)
    readonly property var available: devices.filter(device => device && !device.connected)
    function activate(device) {
        if (device.connected) device.disconnect()
        else if (device.paired) device.connect()
        else device.pair()
    }
    function statusName() {
        if (!adapter) return "no controller"
        if (!adapter.enabled) return "turned off"
        if (connected.length === 1) return connected[0].name || connected[0].deviceName || "one device connected"
        if (connected.length > 1) return connected.length + " devices connected"
        return adapter.discovering ? "scanning" : "nothing connected"
    }
    onOpenChanged: if (adapter && adapter.enabled) adapter.discovering = open

    component DeviceRow: PopupRow {
        required property var device
        shell: root.shell
        icon: device.icon && device.icon.includes("audio") ? "󰋋" : ""
        title: device.name || device.deviceName || device.address
        detail: device.connected ? "Connected" : device.pairing ? "Pairing" : device.paired ? "Paired" : BluetoothDeviceState.toString(device.state)
        value: device.batteryAvailable ? Math.round(device.battery * 100) + "%" : ""
        active: device.connected
        // right-click forgets a paired device that is not currently connected
        onClicked: button => button === Qt.RightButton && device.paired && !device.connected ? device.forget() : root.activate(device)
    }

    Column {
        anchors.fill: parent; spacing: Style.px(14)
        PopupHero { shell: root.shell; title: "Bluetooth"; status: root.statusName() }
        PopupRow {
            width: parent.width; shell: root.shell; icon: ""; title: root.adapter && root.adapter.enabled ? "Bluetooth powered" : "Bluetooth off"; detail: root.adapter ? root.adapter.name : "No controller"; active: root.adapter && root.adapter.enabled
            onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
        }
        PopupSeparator { shell: root.shell }
        PopupSection { visible: root.connected.length > 0; shell: root.shell; text: "CONNECTED" }
        ListView {
            visible: root.connected.length > 0
            width: parent.width; height: Math.min(contentHeight, Style.px(120)); spacing: Style.px(4); clip: true
            model: root.connected
            delegate: DeviceRow { required property var modelData; device: modelData; width: ListView.view.width }
        }
        PopupSeparator { visible: root.connected.length > 0; shell: root.shell }
        PopupSection { shell: root.shell; text: "AVAILABLE"; value: root.adapter && root.adapter.discovering ? "scanning" : "" }
        ListView {
            width: parent.width; height: parent.height - y; spacing: Style.px(4); clip: true
            model: root.available
            delegate: DeviceRow { required property var modelData; device: modelData; width: ListView.view.width }
        }
    }
}

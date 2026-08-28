import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

PopupCard {
    id: root
    popupName: "bluetooth"
    contentWidth: Style.px(380)
    contentHeight: Style.px(420)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
    readonly property var connected: devices.filter(device => device && device.connected)
    readonly property var available: devices.filter(device => device && !device.connected)
    readonly property var pipewireNodes: Pipewire.nodes.values
    property var pendingActions: ({})
    property var pendingAudioDevice: null
    property int pendingAudioAttempts: 0

    function cloneMap(values) {
        const next = ({})
        for (const key in values || {}) next[key] = values[key]
        return next
    }
    function pendingAction(address) { return address && pendingActions[address] ? pendingActions[address] : "" }
    function setPendingAction(address, action) {
        if (!address) return
        const next = cloneMap(pendingActions)
        if (action) next[address] = action
        else delete next[address]
        pendingActions = next
        if (action) pendingTimeout.restart()
    }
    function activate(device) {
        if (!device || !device.address || pendingAction(device.address)) return
        if (device.connected) {
            setPendingAction(device.address, "disconnecting")
            device.disconnect()
        } else if (device.paired || device.bonded || device.trusted) {
            setPendingAction(device.address, "connecting")
            device.connect()
        } else {
            setPendingAction(device.address, "connecting")
            device.pair()
        }
    }
    function forget(device) {
        if (!device || !device.address || pendingAction(device.address)) return
        setPendingAction(device.address, "forgetting")
        device.forget()
    }
    function syncPendingActions() {
        const next = cloneMap(pendingActions)
        let changed = false
        for (const address in next) {
            const action = next[address]
            const device = devices.find(candidate => candidate && candidate.address === address)
            const connectedNow = action === "connecting" && device && device.connected
            if (connectedNow || action === "disconnecting" && device && !device.connected
                    || action === "forgetting" && (!device || !(device.paired || device.bonded || device.trusted))) {
                if (connectedNow) scheduleAudioSwitch(device)
                delete next[address]
                changed = true
            }
        }
        if (changed) pendingActions = next
    }
    function normalizedAddress(value) { return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "") }
    function nodeText(node) {
        const properties = node && node.ready && node.properties ? node.properties : ({})
        return [node ? node.name : "", node ? node.description : "", node ? node.nickname : "",
            properties["node.name"], properties["node.description"], properties["node.nick"],
            properties["device.name"], properties["device.description"], properties["device.product.name"],
            properties["device.alias"], properties["device.string"], properties["api.bluez5.address"],
            properties["bluez5.address"], properties["media.name"]].join(" ").toLowerCase()
    }
    function bluetoothSink(device) {
        const address = normalizedAddress(device ? device.address : "")
        const label = String(device ? device.deviceName || device.name || "" : "").trim().toLowerCase()
        for (const node of pipewireNodes) {
            if (!node || !node.isSink || node.isStream) continue
            const text = nodeText(node)
            if (address && normalizedAddress(text).includes(address) || label && text.includes(label)) return node
        }
        return null
    }
    function scheduleAudioSwitch(device) {
        pendingAudioDevice = ({
            address: device && device.address ? device.address : "",
            name: device && device.name ? device.name : "",
            deviceName: device && device.deviceName ? device.deviceName : ""
        })
        pendingAudioAttempts = 0
        audioSwitchTimer.restart()
    }
    function switchPendingAudioOutput() {
        if (!pendingAudioDevice) return
        const sink = bluetoothSink(pendingAudioDevice)
        if (sink) {
            Pipewire.preferredDefaultAudioSink = sink
            if (sink.id !== undefined && sink.name)
                root.shell.run(["hyprshell", "volume-control.sh", "--set-default", String(sink.id), String(sink.name)])
            pendingAudioDevice = null
            audioSwitchTimer.stop()
            return
        }
        if (++pendingAudioAttempts >= 8) pendingAudioDevice = null
        else audioSwitchTimer.restart()
    }
    function statusName() {
        if (!adapter) return "no controller"
        if (!adapter.enabled) return "turned off"
        if (connected.length === 1) return connected[0].name || connected[0].deviceName || "one device connected"
        if (connected.length > 1) return connected.length + " devices connected"
        return adapter.discovering ? "scanning" : "nothing connected"
    }
    onOpenChanged: if (adapter && adapter.enabled) adapter.discovering = open
    onDevicesChanged: syncPendingActions()

    PwObjectTracker { objects: root.pipewireNodes }
    Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pendingActions = ({}) }
    Timer { id: audioSwitchTimer; interval: 500; onTriggered: root.switchPendingAudioOutput() }
    Repeater {
        model: root.devices
        Item {
            required property var modelData
            width: 0; height: 0
            Connections {
                target: modelData
                function onConnectedChanged() { root.syncPendingActions() }
                function onPairedChanged() { root.syncPendingActions() }
            }
        }
    }

    component DeviceRow: PopupRow {
        required property var device
        readonly property string pending: root.pendingAction(device.address)
        shell: root.shell
        icon: device.icon && device.icon.includes("audio") ? "󰋋" : ""
        title: device.name || device.deviceName || device.address
        detail: pending === "connecting" ? (device.pairing ? "Pairing…" : "Connecting…")
            : pending === "disconnecting" ? "Disconnecting…"
            : pending === "forgetting" ? "Forgetting…"
            : device.connected ? "Connected" : device.pairing ? "Pairing" : device.paired ? "Paired" : BluetoothDeviceState.toString(device.state)
        value: device.batteryAvailable ? Math.round(device.battery * 100) + "%" : ""
        active: device.connected
        interactive: pending === ""
        // right-click forgets a paired device that is not currently connected
        onClicked: button => button === Qt.RightButton && (device.paired || device.bonded || device.trusted) && !device.connected ? root.forget(device) : root.activate(device)
    }

    Column {
        anchors.fill: parent; spacing: Style.px(14)
        PopupHero { shell: root.shell; title: "Bluetooth"; status: root.statusName() }
        PopupRow {
            width: parent.width; shell: root.shell; icon: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"; title: root.adapter && root.adapter.enabled ? "Bluetooth powered" : "Bluetooth off"; detail: root.adapter ? root.adapter.name : "No controller"; active: root.adapter && root.adapter.enabled
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

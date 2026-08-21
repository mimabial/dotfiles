import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Networking

PopupCard {
    id: root
    popupName: "network"
    contentWidth: 380
    contentHeight: 560
    property var pendingNetwork: null
    readonly property var device: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) if (devices[i].type === DeviceType.Wifi) return devices[i]
        return null
    }
    function setAutoconnect(enabled) {
        const uuid = String(root.status.uuid || "")
        if (uuid === "") return
        root.shell.run(["nmcli", "connection", "modify", uuid, "connection.autoconnect", enabled ? "yes" : "no"])
        autoconnectSettle.restart()
    }

    function activate(network) {
        if (network.connected) network.disconnect()
        else if (network.known || network.security === WifiSecurityType.Open) network.connect()
        else { pendingNetwork = network; password.text = ""; password.forceActiveFocus() }
    }
    property var status: ({})
    readonly property var active: {
        const list = device ? device.networks.values : []
        for (const network of list) if (network.connected) return network
        return null
    }
    property real rxRate: 0
    property real txRate: 0
    property var lastSample: null

    function refreshStatus() { if (!statusProc.running) statusProc.running = true }
    function bytes(value) {
        const n = Number(value) || 0
        if (n >= 1024 * 1024 * 1024) return (n / 1024 / 1024 / 1024).toFixed(1) + " GB"
        if (n >= 1024 * 1024) return (n / 1024 / 1024).toFixed(1) + " MB"
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB"
        return n + " B"
    }
    function sample(next) {
        const now = Date.now()
        if (lastSample && next.rx !== null && next.tx !== null) {
            const seconds = Math.max(0.001, (now - lastSample.at) / 1000)
            rxRate = Math.max(0, (next.rx - lastSample.rx) / seconds)
            txRate = Math.max(0, (next.tx - lastSample.tx) / seconds)
        }
        if (next.rx !== null && next.tx !== null) lastSample = { rx: next.rx, tx: next.tx, at: now }
    }
    onOpenChanged: {
        if (device) device.scannerEnabled = open
        if (!open) pendingNetwork = null
        if (open) refreshStatus()
        if (!open) { lastSample = null; rxRate = 0; txRate = 0 }
    }

    property Process statusProc: Process {
        command: ["hyprshell", "system/network-status"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const next = JSON.parse(text) || ({})
                root.sample(next)
                root.status = next
            } catch (error) { root.status = ({}) }
        } }
    }
    property Timer statusTimer: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refreshStatus() }
    // nmcli writes the profile asynchronously; re-read once it has landed
    property Timer autoconnectSettle: Timer { interval: 600; onTriggered: root.refreshStatus() }

    component InfoPair: Row {
        property string label: ""
        property string value: ""
        visible: value !== ""
        width: parent.width; spacing: Style.lg
        Text { id: pairLabel; text: parent.label; color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
        Text { id: pairValue; text: parent.value; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }

    Column {
        anchors.fill: parent; spacing: 14
        PopupSection { shell: root.shell; text: "NETWORK" }
        Row {
            width: parent.width; spacing: Style.xs
            PopupRow {
                width: parent.width - qrAction.width - Style.xs
                shell: root.shell
                icon: Networking.wifiEnabled ? "󰖩" : "󰖪"
                title: Networking.wifiEnabled ? "Wi-Fi powered" : "Wi-Fi off"
                detail: root.device ? root.device.name : "No Wi-Fi adapter"
                active: Networking.wifiEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
            BarButton {
                id: qrAction
                shell: root.shell
                implicitWidth: 44; implicitHeight: 46
                text: "󰐲"; tooltip: "Show QR code"
                fontSize: Style.title
                outline: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
                onClicked: root.shell.togglePopup("wifiqr")
            }
        }
        Column {
            visible: root.active !== null || !!root.status.address
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            // the switch rides on the header line: at header scale it reads as a
            // modifier for the whole section rather than another reading
            Item {
                width: parent.width
                implicitHeight: Math.max(connectionHeader.implicitHeight, autoRow.implicitHeight)

                PopupSection {
                    id: connectionHeader
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    shell: root.shell; text: "CONNECTION"
                }
                Row {
                    id: autoRow
                    visible: String(root.status.uuid || "") !== ""
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.md
                    PopupSection {
                        id: autoLabel
                        shell: root.shell; text: "AUTO-CONNECT"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ToggleSwitch {
                        shell: root.shell
                        checked: root.status.autoconnect === true
                        // PopupSection's topPadding pushes its glyphs below its box
                        // centre; offset so the switch centres on the text, not the box
                        anchors.verticalCenter: autoLabel.verticalCenter
                        anchors.verticalCenterOffset: Math.round(autoLabel.topPadding / 2)
                        onToggled: root.setAutoconnect(!root.status.autoconnect)
                    }
                }
            }
            Item { width: 1; height: 2 }
            InfoPair {
                label: "Signal"
                value: root.active ? Math.round(root.active.signalStrength * 100) + "%" : ""
            }
            InfoPair {
                label: "Security"
                value: root.active ? WifiSecurityType.toString(root.active.security) : ""
            }
            InfoPair { label: "IP address"; value: String(root.status.address || "") }
            InfoPair { label: "Gateway"; value: String(root.status.gateway || "") }
            InfoPair { label: "Band"; value: String(root.status.band || "") }
            InfoPair { label: "DNS"; value: (root.status.dns || []).join(", ") }
            InfoPair {
                label: "Ping"
                value: {
                    const ping = root.status.ping || ({})
                    const parts = []
                    if (ping.router !== null && ping.router !== undefined) parts.push(ping.router + " ms router")
                    if (ping.internet !== null && ping.internet !== undefined) parts.push(ping.internet + " ms internet")
                    return parts.join("  ·  ")
                }
            }
            InfoPair {
                label: "Connectivity"
                value: Networking.canCheckConnectivity ? NetworkConnectivity.toString(Networking.connectivity) : ""
            }
            InfoPair { label: "Downloaded"; value: root.status.rx ? root.bytes(root.status.rx) : "" }
            InfoPair { label: "Uploaded"; value: root.status.tx ? root.bytes(root.status.tx) : "" }
            InfoPair { label: "Receiving"; value: root.lastSample ? root.bytes(root.rxRate) + "/s" : "" }
            InfoPair { label: "Sending"; value: root.lastSample ? root.bytes(root.txRate) + "/s" : "" }
        }

        Text { visible: root.pendingNetwork !== null; text: root.pendingNetwork ? "PASSWORD · " + root.pendingNetwork.name : ""; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: 10; font.bold: true }
        TextField {
            id: password
            visible: root.pendingNetwork !== null
            width: parent.width; height: visible ? 38 : 0
            echoMode: TextInput.Password; placeholderText: "Network password"; color: root.shell.foreground; font.family: root.shell.fontFamily
            background: Rectangle { color: root.shell.alpha(root.shell.foreground, .07); border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .4); radius: root.shell.rounding }
            onAccepted: if (root.pendingNetwork && text) { root.pendingNetwork.connectWithPsk(text); root.pendingNetwork = null }
            Keys.onEscapePressed: root.pendingNetwork = null
        }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: root.device && root.device.scannerEnabled ? "AVAILABLE · SCANNING" : "AVAILABLE" }
        ListView {
            width: parent.width; height: parent.height - y; spacing: 4; clip: true
            model: root.device ? root.device.networks : null
            delegate: PopupRow {
                required property var modelData
                width: ListView.view.width; shell: root.shell
                icon: modelData.connected ? "󰖩" : modelData.security === WifiSecurityType.Open ? "󰖪" : "󰌾"
                title: modelData.name
                detail: modelData.connected ? "Connected" : modelData.stateChanging ? ConnectionState.toString(modelData.state) : modelData.known ? "Saved" : WifiSecurityType.toString(modelData.security)
                value: Math.round(modelData.signalStrength * 100) + "%"
                active: modelData.connected
                onClicked: button => button === Qt.RightButton && modelData.known && !modelData.connected ? modelData.forget() : root.activate(modelData)
            }
        }
    }
}

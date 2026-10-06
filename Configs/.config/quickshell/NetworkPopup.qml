pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Networking

PopupCard {
    id: root
    popupName: "network"
    contentWidth: Style.px(440)
    contentHeight: networkColumn.implicitHeight + padding * 2
    keyboardHint: "↑↓/Tab move · Enter select · R refresh · Ctrl+Tab panel · Esc"
    property var pendingNetwork: null
    property var actionNetwork: null
    property var chosenNetwork: null
    property string actionKind: ""
    property string actionError: ""
    property var connectionSettings: ({bands: [], selectedBand: "auto", dnsMode: "DHCP", dnsServers: ""})
    property bool settingsOpen: false
    property bool editingCustomDns: false
    property bool statusPending: false
    property bool statsHeld: false
    property var speedResult: ({})
    readonly property var selectedNetwork: chosenNetwork || active
    readonly property var traffic: (shell.systemStats.snapshot.net?.ifaces || []).find(item => item.name === root.status.iface) || null
    readonly property var linkTraffic: (shell.systemStats.snapshot.net?.ifaces || []).find(item => item.name === root.status.profileIface) || null
    readonly property bool portal: Networking.canCheckConnectivity && Networking.connectivityCheckEnabled && Networking.connectivity === NetworkConnectivity.Portal
    readonly property var device: {
        const devices = Networking.devices.values
        for (let i = 0; i < devices.length; ++i) if (devices[i].type === DeviceType.Wifi) return devices[i]
        return null
    }
    function setAutoconnect(enabled) {
        const uuid = String(root.status.uuid || "")
        if (uuid === "") return
        runSetting(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", enabled ? "yes" : "no"])
    }

    function runSetting(command) {
        if (settingsAction.running) return
        actionError = ""
        settingsAction.command = command
        settingsAction.running = true
    }
    function setConnectionSetting(action, value, servers) {
        runSetting([shell.home + "/.local/lib/hypr/system/network-settings.py", action,
            String(status.uuid), String(status.profileIface || status.iface), value, servers || ""])
    }
    function refreshSettings() {
        if (!open || !status.uuid || settingsProc.running) return
        settingsProc.command = [shell.home + "/.local/lib/hypr/system/network-settings.py", "status", String(status.uuid), String(status.profileIface || status.iface)]
        settingsProc.running = true
    }
    function promptPassword(network) {
        pendingNetwork = network
        password.text = ""
        password.forceActiveFocus()
    }
    function runNetworkAction(network, kind) {
        if (!network || actionKind !== "") return
        actionError = ""
        actionNetwork = network
        actionKind = kind
        if (kind === "disconnect") network.disconnect()
        else if (kind === "forget") network.forget()
        else if (pendingNetwork === network) network.connectWithPsk(password.text)
        else network.connect()
    }
    function finishAction() {
        if (!actionNetwork || actionKind === "") return
        if (actionKind === "connect" ? !actionNetwork.connected
            : actionKind === "disconnect" ? actionNetwork.connected : actionNetwork.known) return
        actionKind = ""
        actionNetwork = null
        pendingNetwork = null
        refreshStatus()
    }
    function failAction(reason) {
        const network = actionNetwork
        actionKind = ""
        actionNetwork = null
        actionError = ConnectionFailReason.toString(reason)
        if (network && (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)) {
            if (supportsPassword(network)) promptPassword(network)
            else openEditor()
        }
    }
    function supportsPassword(network) { return [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security) }
    function openEditor() {
        shell.closePopup()
        shell.run(["nm-connection-editor"])
    }

    function activate(network) {
        chosenNetwork = network
        if (network.connected) runNetworkAction(network, "disconnect")
        else if (network.known || network.security === WifiSecurityType.Open || network.security === WifiSecurityType.Owe) runNetworkAction(network, "connect")
        else if (supportsPassword(network)) promptPassword(network)
        else openEditor()
    }
    property var status: ({})
    readonly property var active: {
        const list = device ? device.networks.values : []
        for (const network of list) if (network.connected) return network
        return null
    }
    function statusName() {
        if (root.status.address && root.status.profileIface && root.status.profileIface !== root.device?.name) return root.status.profileIface
        if (!Networking.wifiEnabled) return "wi-fi off"
        if (!root.active) return "not connected"
        return root.active.name || "connected"
    }
    function pingText(key) { const ms = (root.status.ping || ({}))[key]; return ms === null || ms === undefined ? "" : ms + " ms" }
    // split by family, not by index: resolv.conf order is whatever was pushed
    function dnsFor(v6) { return (root.status.dns || []).filter(entry => String(entry).includes(":") === v6).join(", ") }
    function refreshStatus() {
        if (!open) return
        if (statusProc.running) { statusPending = true; return }
        statusProc.running = true
    }
    function bytes(value) {
        const n = Number(value) || 0
        if (n >= 1024 * 1024 * 1024) return (n / 1024 / 1024 / 1024).toFixed(1) + " GB"
        if (n >= 1024 * 1024) return (n / 1024 / 1024).toFixed(1) + " MB"
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB"
        return Math.round(n) + " B"
    }
    function handleKey(event) {
        if (event.key === Qt.Key_R) { refreshStatus(); refreshSettings(); return true }
        if (event.key === Qt.Key_Escape && pendingNetwork) { pendingNetwork = null; return true }
        return defaultKey(event)
    }
    onOpenChanged: {
        if (device) device.scannerEnabled = open
        if (!open) pendingNetwork = null
        if (open) { chosenNetwork = null; refreshStatus(); shell.systemStats.acquireDetail(); statsHeld = true }
        else {
            if (statsHeld) { shell.systemStats.releaseDetail(); statsHeld = false }
            statusPending = false
            if (speedProc.running) speedProc.running = false
        }
    }
    Component.onDestruction: if (statsHeld && shell.systemStats) shell.systemStats.releaseDetail()

    property Connections actionEvents: Connections {
        target: root.actionNetwork
        function onConnectionFailed(reason) { root.failAction(reason) }
        function onConnectedChanged() { root.finishAction() }
        function onKnownChanged() { root.finishAction() }
    }
    property Connections networkEvents: Connections {
        target: Networking
        function onConnectivityChanged() { root.refreshStatus() }
        function onWifiEnabledChanged() { root.refreshStatus() }
    }
    property Connections selectionEvents: Connections {
        target: root
        function onCursorIndexChanged() {
            const row = root.navigableRows[root.cursorIndex]
            if (row && "network" in row) root.chosenNetwork = row.network
        }
    }

    property Process statusProc: Process {
        command: ["bash", root.shell.home + "/.local/lib/hypr/system/network-status.sh"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const next = JSON.parse(text) || ({})
                root.status = next
                root.refreshSettings()
            } catch (error) { root.status = ({}) }
        } }
        onExited: {
            if (root.statusPending) { root.statusPending = false; Qt.callLater(root.refreshStatus) }
        }
    }
    property Process routeEvents: Process {
        command: ["ip", "monitor", "link", "address", "route"]
        running: root.open
        stdout: SplitParser { onRead: root.refreshStatus() }
    }
    property Process settingsProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.connectionSettings = JSON.parse(text); if (!customDns.activeFocus) customDns.text = root.connectionSettings.dnsServers }
            catch (error) { root.actionError = "Could not read connection settings." }
        } }
        stderr: StdioCollector { id: settingsError; waitForEnd: true }
        onExited: code => { if (code !== 0) root.actionError = String(settingsError.text).trim() }
    }
    property Process settingsAction: Process {
        stderr: StdioCollector { id: actionStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.actionError = String(actionStderr.text).trim()
            else root.editingCustomDns = false
            root.refreshStatus()
        }
    }
    property Process speedProc: Process {
        command: [root.shell.home + "/.local/lib/hypr/system/network-speedtest.py"]
        stdout: SplitParser { onRead: data => { try { root.speedResult = JSON.parse(data) } catch (error) {} } }
    }

    // paired left/right so conjugate readings sit on one line; a cell keeps its
    // place and reads "—" when empty, or the pairing shifts as probes land
    component InfoDuo: Row {
        id: duo
        property string label1: ""; property string value1: ""
        property string label2: ""; property string value2: ""
        width: parent.width; spacing: Style.xxl
        PopupInfoPair { width: (duo.width - duo.spacing) / 2; shell: root.shell; label: duo.label1; value: duo.value1 }
        PopupInfoPair { width: (duo.width - duo.spacing) / 2; shell: root.shell; label: duo.label2; value: duo.value2 }
    }

    Column {
        id: networkColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        PopupHero { shell: root.shell; title: "Network"; status: root.statusName() }
        Row {
            width: parent.width; spacing: Style.xs
            PopupRow {
                id: wifiRow
                width: parent.width - qrAction.width - Style.xs
                shell: root.shell
                icon: Networking.wifiEnabled ? "󰖩" : "󰖪"
                title: Networking.wifiEnabled ? "Wi-Fi powered" : "Wi-Fi off"
                detail: root.device ? root.device.name : "No Wi-Fi adapter"
                active: Networking.wifiEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
            PopupIconButton { id: qrAction; shell: root.shell; implicitHeight: wifiRow.implicitHeight; glyph: "󰐲"; hint: "Show QR code"; onClicked: root.shell.togglePopup("wifiqr") }
        }
        PopupRow { visible: root.portal; width: parent.width; shell: root.shell; icon: "󰖟"; title: "Open captive portal"; detail: "Sign in to access the internet"; onClicked: { root.shell.closePopup(); root.shell.run(["xdg-open", "http://ping.archlinux.org/nm-check.txt"]) } }
        Text { visible: root.actionError !== ""; width: parent.width; text: root.actionError; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.shell.urgent; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
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
            InfoDuo { label1: "Signal"; value1: root.active ? Math.round(root.active.signalStrength * 100) + "%" : ""; label2: "Security"; value2: root.active ? WifiSecurityType.toString(root.active.security) : "" }
            Row {
                width: parent.width; spacing: Style.xxl
                PopupInfoPair { width: (parent.width - parent.spacing) / 2; shell: root.shell; label: "IP address"; value: String(root.status.address || ""); interactive: value !== ""; onClicked: root.shell.run(["wl-copy", value]) }
                PopupInfoPair { width: (parent.width - parent.spacing) / 2; shell: root.shell; label: "Gateway"; value: String(root.status.gateway || ""); interactive: value !== ""; onClicked: root.shell.run(["wl-copy", value]) }
            }
            InfoDuo { label1: "Router ping"; value1: root.pingText("router"); label2: "Internet ping"; value2: root.pingText("internet") }
            InfoDuo { label1: "Band"; value1: String(root.status.band || ""); label2: "Connectivity"; value2: Networking.canCheckConnectivity ? ({[NetworkConnectivity.Full]: "Full", [NetworkConnectivity.Limited]: "Limited", [NetworkConnectivity.Portal]: "Captive portal", [NetworkConnectivity.None]: "None"})[Networking.connectivity] || "" : "" }
            InfoDuo { label1: "Downloaded"; value1: root.bytes(root.traffic?.rxTotal ?? root.status.rx); label2: "Uploaded"; value2: root.bytes(root.traffic?.txTotal ?? root.status.tx) }
            InfoDuo { label1: "Receiving"; value1: root.traffic ? root.bytes(root.traffic.rx) + "/s" : ""; label2: "Sending"; value2: root.traffic ? root.bytes(root.traffic.tx) + "/s" : "" }
            InfoDuo { label1: "Packet loss"; value1: root.status.packetLoss == null ? "" : root.status.packetLoss + "%"; label2: "Traffic interface"; value2: String(root.status.iface || "") }
            InfoDuo { label1: "Connection interface"; value1: String(root.status.profileIface || ""); label2: "Link speed"; value2: root.linkTraffic?.speed > 0 ? root.linkTraffic.speed + " Mb/s" : "" }
            InfoDuo { visible: value1 !== "" || value2 !== ""; label1: "DNS"; value1: root.dnsFor(false); label2: "DNS IPv6"; value2: root.dnsFor(true) }
        }

        Column {
            visible: !!root.status.uuid
            width: parent.width; spacing: Style.sm
            PopupRow { width: parent.width; shell: root.shell; icon: "󰒓"; title: "Connection settings"; detail: "DNS and Wi-Fi band"; active: root.settingsOpen; onClicked: { root.settingsOpen = !root.settingsOpen; root.refreshSettings() } }
            Column {
                visible: root.settingsOpen
                width: parent.width; spacing: Style.sm
                PopupSelect { width: parent.width; shell: root.shell; choices: ["DHCP", "Cloudflare", "Google", "Custom"].map(label => ({label: label, value: label})); selectedIndex: root.editingCustomDns ? 3 : Math.max(0, ["DHCP", "Cloudflare", "Google", "Custom"].indexOf(root.connectionSettings.dnsMode)); enabled: !root.settingsAction.running; onActivated: index => { root.editingCustomDns = index === 3; if (index === 3) customDns.forceActiveFocus(); else root.setConnectionSetting("dns", choices[index].value) } }
                PopupField { id: customDns; visible: root.editingCustomDns || root.connectionSettings.dnsMode === "Custom"; width: parent.width; shell: root.shell; placeholderText: "DNS server addresses"; enabled: !root.settingsAction.running; onAccepted: root.setConnectionSetting("dns", "Custom", text) }
                PopupRow { visible: customDns.visible; width: parent.width; shell: root.shell; title: "Apply custom DNS"; enabled: customDns.text.trim() !== "" && !root.settingsAction.running; onClicked: root.setConnectionSetting("dns", "Custom", customDns.text) }
                PopupSection { visible: root.connectionSettings.bands.length > 1 || root.connectionSettings.selectedBand !== "auto"; shell: root.shell; text: "WI-FI BAND" }
                PopupSelect { visible: root.connectionSettings.bands.length > 1 || root.connectionSettings.selectedBand !== "auto"; width: parent.width; shell: root.shell; choices: [{label: "Automatic", value: "auto"}].concat(root.connectionSettings.bands.map(band => ({label: band + " GHz", value: band}))); selectedIndex: Math.max(0, choices.findIndex(choice => choice.value === root.connectionSettings.selectedBand)); enabled: !root.settingsAction.running; onActivated: index => root.setConnectionSetting("band", choices[index].value) }
            }
        }
        Column {
            visible: !!root.status.iface
            width: parent.width; spacing: Style.sm
            PopupRow { width: parent.width; shell: root.shell; icon: "󰓅"; title: root.speedProc.running ? "Cancel speed test" : "Run speed test"; detail: root.speedProc.running ? "Measuring " + root.speedResult.phase : "Download and upload · Cloudflare"; onClicked: { if (root.speedProc.running) root.speedProc.running = false; else { root.speedResult = ({}); root.speedProc.running = true } } }
            InfoDuo { visible: root.speedResult.download != null || root.speedResult.upload != null; label1: "Download"; value1: root.speedResult.download == null ? "" : root.speedResult.download + " Mbps"; label2: "Upload"; value2: root.speedResult.upload == null ? "" : root.speedResult.upload + " Mbps" }
            Text { visible: !!root.speedResult.error; width: parent.width; text: String(root.speedResult.error || ""); wrapMode: Text.Wrap; color: root.shell.urgent; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        }

        Column {
            visible: root.pendingNetwork !== null
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: root.pendingNetwork ? "PASSWORD · " + root.pendingNetwork.name : "" }
            PopupField {
                id: password
                width: parent.width; shell: root.shell
                enabled: root.actionKind === ""
                echoMode: TextInput.Password; placeholderText: "Network password"
                onAccepted: if (root.pendingNetwork && text) root.runNetworkAction(root.pendingNetwork, "connect")
                Keys.onEscapePressed: root.pendingNetwork = null
            }
            PopupRow { width: parent.width; shell: root.shell; title: root.actionKind === "connect" ? "Connecting…" : "Connect"; enabled: password.text !== "" && root.actionKind === ""; onClicked: root.runNetworkAction(root.pendingNetwork, "connect") }
        }
        PopupSeparator { shell: root.shell }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "AVAILABLE"; value: root.device && root.device.scannerEnabled ? "scanning" : "" }
            ListView {
                width: parent.width; height: Math.min(contentHeight, Style.px(240)); spacing: Style.sm; clip: true
                ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                model: root.device ? root.device.networks : null
                delegate: PopupRow {
                    required property var modelData
                    readonly property var network: modelData
                    width: ListView.view.width; shell: root.shell
                    icon: modelData.connected ? "󰖩" : modelData.security === WifiSecurityType.Open ? "󰖪" : "󰌾"
                    title: modelData.name
                    detail: modelData.connected ? "Connected" : modelData.stateChanging ? ConnectionState.toString(modelData.state) : modelData.known ? "Saved" : WifiSecurityType.toString(modelData.security)
                    value: Math.round(modelData.signalStrength * 100) + "%"
                    active: modelData.connected
                    enabled: root.actionKind === ""
                    onClicked: button => button === Qt.RightButton && modelData.known && !modelData.connected ? root.runNetworkAction(modelData, "forget") : root.activate(modelData)
                }
            }
            PopupRow { visible: root.selectedNetwork?.connected === true; width: parent.width; shell: root.shell; title: "Disconnect " + (root.selectedNetwork?.name || ""); enabled: root.actionKind === ""; onClicked: root.runNetworkAction(root.selectedNetwork, "disconnect") }
            PopupRow { visible: root.selectedNetwork?.known === true; width: parent.width; shell: root.shell; title: "Forget " + (root.selectedNetwork?.name || ""); enabled: root.actionKind === ""; onClicked: root.runNetworkAction(root.selectedNetwork, "forget") }
            PopupRow { width: parent.width; shell: root.shell; title: "Network settings…"; detail: "Enterprise Wi-Fi and saved connections"; onClicked: root.openEditor() }
        }
    }
}

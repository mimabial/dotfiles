pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Ui" as Ui
import "Commons" as Commons
import "BluetoothModel.js" as Model

PopupCard {
    id: root
    popupName: "bluetooth"
    contentWidth: Style.px(440)
    contentHeight: Style.px(570)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var defaultAudioSink: Pipewire.defaultAudioSink
    readonly property var defaultAudioSource: Pipewire.defaultAudioSource
    property int deviceRevision: 0
    readonly property var deviceGroups: {
        const revision = deviceRevision
        return Model.deviceLists(devices)
    }
    readonly property var connectedDevices: deviceGroups.connected || []
    readonly property var knownDevices: deviceGroups.known || []
    readonly property var discoveredDevices: deviceGroups.discovered || []
    readonly property var connectedRows: connectedDevices.map(Model.deviceRow)
    readonly property var knownRows: knownDevices.map(Model.deviceRow)
    readonly property var discoveredRows: discoveredDevices.map(Model.deviceRow)

    property string page: "devices"
    property string selectedAddress: ""
    readonly property var selectedRow: rowByAddress(selectedAddress)
    property bool renameEditing: false
    property string actionError: ""
    property string propertyError: ""
    property string profileError: ""
    property bool forgetConfirmation: false

    property var pendingActions: ({})
    property var pendingKinds: ({})
    property var pendingDeadlines: ({})
    property var deviceActionFailures: ({})
    property var activeDeviceAction: null
    property bool cancelRequested: false
    readonly property bool deviceActionBusy: deviceActionProc.running
    readonly property bool devicePropertyBusy: propertyProc.running
    readonly property bool audioProfileBusy: profileSetProc.running
    readonly property bool powerBusy: powerProc.running

    property var audioProfiles: ({})
    property var pendingAudioProfile: null
    property var connectionStates: ({})
    property bool connectionBaselineReady: false
    property var policyQueue: ({})
    property bool owesDiscoveryStop: false
    readonly property bool scanWanted: open && page === "devices" && adapter && adapter.enabled

    readonly property var audioPolicies: {
        try {
            const parsed = JSON.parse(String(shell.store.bluetoothAudioPolicies || "{}"))
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
        } catch (error) { return ({}) }
    }

    function deviceByAddress(address) {
        const key = Model.normalizedAddress(address)
        for (const device of devices)
            if (device && Model.normalizedAddress(device.address) === key) return device
        return null
    }
    function rowByAddress(address) {
        const device = deviceByAddress(address)
        return device ? Model.deviceRow(device) : null
    }
    function displayName(device) { return Model.deviceLabel(device) || "Bluetooth device" }
    function profileState(address) { return Model.audioProfileState(audioProfiles, address) }
    function profileOptions(address) { return Model.audioProfileOptions(profileState(address)) }
    function currentCodec(address) {
        const state = profileState(address)
        return Model.audioProfileCodec(state, state ? state.activeProfile : "")
    }
    function bluetoothAudioSink(device) {
        for (const node of pipewireNodes)
            if (Model.bluetoothSinkMatchesDevice(node, device, devices)) return node
        return null
    }
    function bluetoothAudioSource(device) {
        for (const node of pipewireNodes)
            if (Model.bluetoothSourceMatchesDevice(node, device, devices)) return node
        return null
    }
    function usingForAudio(device) {
        return Model.sameAudioNode(bluetoothAudioSink(device), defaultAudioSink)
    }
    function isAudioDevice(device) {
        return !!device && (Model.isAudioDevice(device.icon, displayName(device))
            || !!profileState(device.address) || !!bluetoothAudioSink(device))
    }

    function cloneMap(values) { return Model.cloneMap(values) }
    function mapValue(values, address) {
        const key = Model.normalizedAddress(address)
        return key && values && values[key] !== undefined ? values[key] : null
    }
    function pendingAction(address) { return String(mapValue(pendingActions, address) || "") }
    function pendingKind(address) { return String(mapValue(pendingKinds, address) || "") }
    function actionFailure(address) { return mapValue(deviceActionFailures, address) }
    function setMapValue(values, address, value) {
        const key = Model.normalizedAddress(address)
        const next = cloneMap(values)
        if (!key) return next
        if (value === null || value === undefined || value === "") delete next[key]
        else next[key] = value
        return next
    }
    function setPending(address, label, kind, deadline) {
        pendingActions = setMapValue(pendingActions, address, label)
        pendingKinds = setMapValue(pendingKinds, address, kind)
        pendingDeadlines = setMapValue(pendingDeadlines, address,
            label ? Number(deadline || Date.now() + 45000) : null)
    }
    function setActionFailure(address, action, message) {
        deviceActionFailures = setMapValue(deviceActionFailures, address,
            action && message ? { action: action, message: message } : null)
    }
    function actionReached(kind, device) {
        if (kind === "pair" || kind === "connect") return !!device && device.connected
        if (kind === "disconnect") return !device || !device.connected
        if (kind === "forget") return !device || !(device.paired || device.bonded || device.trusted || device.blocked)
        return false
    }
    function syncPendingActions() {
        const actions = cloneMap(pendingActions)
        for (const key in actions) {
            const kind = String(pendingKinds[key] || "")
            const device = deviceByAddress(key)
            if (actionReached(kind, device)) {
                setPending(key, "", "")
                setActionFailure(key, "", "")
            }
        }
    }
    function expirePendingActions() {
        syncPendingActions()
        const now = Date.now()
        for (const key in pendingActions) {
            if (activeDeviceAction && Model.normalizedAddress(activeDeviceAction.address) === key
                    && deviceActionProc.running) continue
            if (Number(pendingDeadlines[key] || 0) > now) continue
            const kind = String(pendingKinds[key] || "")
            const labels = {
                pair: "The device did not finish pairing.",
                connect: "The device did not finish connecting.",
                disconnect: "The device stayed connected.",
                forget: "The device was not forgotten."
            }
            setActionFailure(key, kind, labels[kind] || "Bluetooth did not report the requested state.")
            setPending(key, "", "")
        }
    }

    function runDeviceAction(device, action) {
        if (!device || !device.address || deviceActionProc.running || propertyProc.running
                || profileSetProc.running || pendingAction(device.address)) return
        const labels = { pair: "pairing", connect: "connecting", disconnect: "disconnecting", forget: "forgetting" }
        actionError = ""
        setActionFailure(device.address, "", "")
        setPending(device.address, labels[action], action)
        activeDeviceAction = { address: String(device.address), action: action }
        cancelRequested = false
        deviceActionProc.command = ["hyprshell", "bluetooth/device-action", action, String(device.address)]
        deviceActionProc.running = true
    }
    function activateDevice(device) {
        if (!device) return
        if (device.connected) runDeviceAction(device, "disconnect")
        else runDeviceAction(device, device.paired || device.bonded || device.trusted ? "connect" : "pair")
    }
    function togglePower() {
        if (!adapter || powerBusy) return
        actionError = ""
        powerProc.command = ["hyprshell", "bluetooth/power", adapter.enabled ? "off" : "on"]
        powerProc.running = true
    }
    function retryDevice(device) {
        const failure = device ? actionFailure(device.address) : null
        if (failure) runDeviceAction(device, String(failure.action || "connect"))
    }
    function cancelPairing(device) {
        if (!device || !activeDeviceAction || activeDeviceAction.action !== "pair"
                || Model.normalizedAddress(activeDeviceAction.address) !== Model.normalizedAddress(device.address)) return
        cancelRequested = true
        setPending(device.address, "", "")
        if (typeof device.cancelPair === "function") device.cancelPair()
        deviceActionProc.signal(15)
    }

    function refreshAudioProfiles() {
        if (!profilesProc.running && (connectedDevices.length || Object.keys(policyQueue).length))
            profilesProc.running = true
    }
    function setAudioProfile(address, profile, policyKey) {
        if (!address || !profile || profileSetProc.running || deviceActionProc.running || propertyProc.running) return false
        profileError = ""
        pendingAudioProfile = { address: Model.normalizedAddress(address), profile: String(profile), policyKey: String(policyKey || "") }
        profileSetProc.command = ["hyprshell", "bluetooth/profile-set", String(address), String(profile)]
        profileSetProc.running = true
        return true
    }
    function setDefaultAudioSink(sink) {
        if (!sink) return
        Pipewire.preferredDefaultAudioSink = sink
        if (sink.id !== undefined && sink.name)
            shell.run(["hyprshell", "controls/volume-control", "--set-default", String(sink.id), String(sink.name)])
    }
    function setDefaultAudioSource(source) {
        if (source) Pipewire.preferredDefaultAudioSource = source
    }
    function useDeviceForAudio(device) {
        const sink = bluetoothAudioSink(device)
        if (!sink) { actionError = "This device has no available audio output."; return false }
        setDefaultAudioSink(sink)
        setDefaultAudioSource(bluetoothAudioSource(device))
        actionError = ""
        return true
    }

    function policyFor(address) {
        const value = String(audioPolicies[Model.normalizedAddress(address)] || "manual")
        return value === "output" || value === "output-mic" ? value : "manual"
    }
    function policyLabel(value) {
        return value === "output" ? "Output" : value === "output-mic" ? "Output + microphone" : "Manual"
    }
    function setPolicy(address, policy) {
        const key = Model.normalizedAddress(address)
        if (!key) return
        const next = cloneMap(audioPolicies)
        if (policy === "output" || policy === "output-mic") next[key] = policy
        else delete next[key]
        shell.store.bluetoothAudioPolicies = JSON.stringify(next)
    }
    function stepPolicy(address, direction) {
        const order = ["manual", "output", "output-mic"]
        const index = order.indexOf(policyFor(address))
        setPolicy(address, order[(index + (direction < 0 ? 2 : 1)) % order.length])
    }
    function initializeConnections() {
        const states = {}
        for (const device of devices) {
            const key = Model.normalizedAddress(device ? device.address : "")
            if (key) states[key] = !!device.connected
        }
        connectionStates = states
        connectionBaselineReady = true
    }
    function observeConnections() {
        if (!connectionBaselineReady) return initializeConnections()
        const next = {}
        for (const device of devices) {
            const key = Model.normalizedAddress(device ? device.address : "")
            if (!key) continue
            const connected = !!device.connected
            if (connected && connectionStates[key] === false && popupEnabled) queuePolicy(device)
            next[key] = connected
        }
        connectionStates = next
    }
    function queuePolicy(device) {
        const policy = policyFor(device.address)
        if (policy === "manual") return
        const key = Model.normalizedAddress(device.address)
        const next = cloneMap(policyQueue)
        next[key] = { policy: policy, attempts: 0, switchRequested: false, switchWait: 0 }
        policyQueue = next
        refreshAudioProfiles()
    }
    function removeQueuedPolicy(key, message) {
        const next = cloneMap(policyQueue)
        delete next[key]
        policyQueue = next
        if (message) actionError = message
    }
    function applyPolicies() {
        if (!popupEnabled || deviceActionProc.running || propertyProc.running || profileSetProc.running) return
        const next = cloneMap(policyQueue)
        let changed = false
        for (const key in next) {
            const entry = cloneMap(next[key])
            const device = deviceByAddress(key)
            const policy = device ? policyFor(device.address) : "manual"
            if (!device || !device.connected || policy === "manual") { delete next[key]; changed = true; continue }
            entry.policy = policy
            entry.attempts = Number(entry.attempts || 0) + 1
            if (entry.attempts > 90) { delete next[key]; changed = true; continue }
            const sink = bluetoothAudioSink(device)
            if (policy === "output") {
                if (sink) { useDeviceForAudio(device); delete next[key] }
                else next[key] = entry
                changed = true
                continue
            }

            const state = profileState(device.address)
            if (!state) { next[key] = entry; changed = true; refreshAudioProfiles(); continue }
            const duplex = Model.duplexProfileOption(state)
            if (duplex && !Model.audioProfileHasInput(state, state.activeProfile)) {
                if (entry.switchRequested) {
                    entry.switchWait = Number(entry.switchWait || 0) + 1
                    if (entry.switchWait > 8) { entry.switchRequested = false; entry.switchWait = 0 }
                } else if (setAudioProfile(device.address, duplex.value, key)) {
                    entry.switchRequested = true
                }
                next[key] = entry
                changed = true
                continue
            }
            const source = bluetoothAudioSource(device)
            if (sink && (!duplex || source)) {
                setDefaultAudioSink(sink)
                if (source) setDefaultAudioSource(source)
                delete next[key]
            } else next[key] = entry
            changed = true
        }
        if (changed) policyQueue = next
    }

    function openDetails(device) {
        if (!device) return
        selectedAddress = String(device.address || "")
        renameEditing = false
        propertyError = ""
        forgetConfirmation = false
        page = "details"
    }
    function openProfiles(device) {
        if (!device) return
        selectedAddress = String(device.address || "")
        profileError = ""
        page = "profiles"
        refreshAudioProfiles()
    }
    function showDevices() {
        renameEditing = false
        forgetConfirmation = false
        page = "devices"
    }
    function beginRename() {
        if (!selectedRow || propertyProc.running) return
        renameField.text = displayName(selectedRow)
        renameEditing = true
        Qt.callLater(() => { renameField.forceActiveFocus(); renameField.selectAll() })
    }
    function commitRename() {
        const value = String(renameField.text || "").trim()
        if (!value) { propertyError = "Device name cannot be empty."; return }
        updateProperty("name", value, value)
    }
    function updateProperty(name, value, expected) {
        if (!selectedRow || !selectedRow.dbusPath || propertyProc.running || deviceActionProc.running) return
        propertyError = ""
        propertyProc.propertyName = name
        propertyProc.expected = expected
        propertyProc.address = selectedRow.address
        propertyProc.command = ["hyprshell", "bluetooth/device-property", name,
            String(selectedRow.dbusPath), String(value)]
        propertyProc.running = true
    }
    function toggleProperty(name) {
        if (!selectedRow) return
        const next = !selectedRow[name]
        updateProperty(name, next ? "true" : "false", next)
    }
    function confirmForgetDevice() {
        const device = deviceByAddress(selectedAddress)
        forgetConfirmation = false
        showDevices()
        if (device) runDeviceAction(device, "forget")
    }
    function bumpDevices() {
        deviceRevision++
        syncPendingActions()
        observeConnections()
        if (selectedAddress && !deviceByAddress(selectedAddress)) showDevices()
    }

    function primeCursor() {
        rebuildRows()
        cursorIndex = navigableRows.length ? 0 : -1
    }
    function currentNavigableRow() {
        rebuildRows()
        return cursorIndex >= 0 && cursorIndex < navigableRows.length ? navigableRows[cursorIndex] : null
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape && page !== "devices") { showDevices(); return true }
        if (event.key === Qt.Key_J) { moveCursor(1); return true }
        if (event.key === Qt.Key_K) { moveCursor(-1); return true }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left
                || event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            const row = currentNavigableRow()
            if (row && row.adjustKeyboard) row.adjustKeyboard(event.key === Qt.Key_H || event.key === Qt.Key_Left ? -1 : 1)
            return true
        }
        if (event.key === Qt.Key_X && page === "devices") {
            const row = currentNavigableRow()
            if (row && row.dev && (row.dev.paired || row.dev.bonded || row.dev.trusted || row.dev.connected)) {
                openDetails(deviceByAddress(row.dev.address)); forgetConfirmation = true
            }
            return true
        }
        return defaultKey(event)
    }

    onPageChanged: { clearCursor(); Qt.callLater(primeCursor) }
    onOpenChanged: {
        if (open) {
            page = "devices"
            actionError = ""
            refreshAudioProfiles()
            Qt.callLater(primeCursor)
        } else {
            renameEditing = false
            forgetConfirmation = false
        }
    }
    onDevicesChanged: bumpDevices()

    Component.onCompleted: {
        Commons.Style.shell = shell
        Commons.Color.shell = shell
        initializeConnections()
    }

    PwObjectTracker { objects: root.pipewireNodes.filter(node => node && node.audio) }

    Repeater {
        model: root.devices
        Item {
            id: deviceWatcher
            required property var modelData
            width: 0; height: 0
            Connections {
                target: deviceWatcher.modelData
                ignoreUnknownSignals: true
                function onConnectedChanged() { root.bumpDevices() }
                function onPairedChanged() { root.bumpDevices() }
                function onBondedChanged() { root.bumpDevices() }
                function onTrustedChanged() { root.bumpDevices() }
                function onBlockedChanged() { root.bumpDevices() }
                function onWakeAllowedChanged() { root.bumpDevices() }
                function onNameChanged() { root.bumpDevices() }
                function onDeviceNameChanged() { root.bumpDevices() }
                function onBatteryChanged() { root.bumpDevices() }
                function onBatteryAvailableChanged() { root.bumpDevices() }
                function onPairingChanged() { root.bumpDevices() }
                function onStateChanged() { root.bumpDevices() }
            }
        }
    }

    Timer {
        id: discoveryRetry
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.scanWanted && root.adapter && !root.adapter.discovering
        onTriggered: { root.owesDiscoveryStop = true; root.adapter.discovering = true }
    }
    Timer {
        id: discoveryStop
        interval: 700; repeat: true
        property int attempts: 0
        running: !root.scanWanted && root.owesDiscoveryStop && root.adapter && root.adapter.discovering
        onRunningChanged: if (running) attempts = 0
        onTriggered: {
            if (++attempts > 3) { root.owesDiscoveryStop = false; return }
            root.adapter.discovering = false
        }
    }
    Connections {
        target: root.adapter
        ignoreUnknownSignals: true
        function onDiscoveringChanged() { if (!root.adapter.discovering) root.owesDiscoveryStop = false }
    }
    Timer { interval: 500; repeat: true; running: Object.keys(root.pendingActions).length > 0; onTriggered: root.expirePendingActions() }
    Timer { interval: 2000; repeat: true; running: root.open && root.connectedDevices.length > 0; onTriggered: root.refreshAudioProfiles() }
    Timer { interval: 500; repeat: true; triggeredOnStart: true; running: root.popupEnabled && Object.keys(root.policyQueue).length > 0; onTriggered: { root.refreshAudioProfiles(); root.applyPolicies() } }

    Process {
        id: deviceActionProc
        stderr: StdioCollector { id: deviceActionStderr; waitForEnd: true }
        onExited: code => {
            const operation = root.activeDeviceAction
            root.activeDeviceAction = null
            if (!operation) return
            if (root.cancelRequested) {
                root.cancelRequested = false
                root.setPending(operation.address, "", "")
                return
            }
            if (code !== 0) {
                const message = String(deviceActionStderr.text || "Bluetooth operation failed.").trim()
                root.setPending(operation.address, "", "")
                root.setActionFailure(operation.address, operation.action, message)
                root.actionError = message
            } else {
                root.pendingDeadlines = root.setMapValue(root.pendingDeadlines,
                    operation.address, Date.now() + 6000)
                root.syncPendingActions()
            }
        }
    }
    Process {
        id: propertyProc
        property string propertyName: ""
        property string address: ""
        property var expected: null
        stderr: StdioCollector { id: propertyStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.propertyError = String(propertyStderr.text || "Could not change this setting.").trim()
            else {
                root.propertyError = ""
                if (propertyName === "name") root.renameEditing = false
            }
            root.bumpDevices()
        }
    }
    Process {
        id: profilesProc
        command: ["hyprshell", "bluetooth/profiles"]
        stdout: StdioCollector { id: profilesStdout; waitForEnd: true }
        stderr: StdioCollector { id: profilesStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) {
                root.profileError = String(profilesStderr.text || "Could not read Bluetooth audio modes.").trim()
                return
            }
            try {
                const parsed = JSON.parse(String(profilesStdout.text || "{}"))
                root.audioProfiles = parsed && typeof parsed === "object" ? parsed : ({})
                if (root.pendingAudioProfile) {
                    const state = root.profileState(root.pendingAudioProfile.address)
                    if (state && state.activeProfile === root.pendingAudioProfile.profile)
                        root.pendingAudioProfile = null
                }
            } catch (error) { root.profileError = "Bluetooth audio returned invalid profile data." }
        }
    }
    Process {
        id: profileSetProc
        stderr: StdioCollector { id: profileSetStderr; waitForEnd: true }
        onExited: code => {
            const operation = root.pendingAudioProfile
            if (code !== 0) {
                const message = String(profileSetStderr.text || "Could not change the Bluetooth audio mode.").trim()
                root.profileError = message
                if (operation && operation.policyKey) root.removeQueuedPolicy(operation.policyKey,
                    "Automatic Bluetooth audio routing failed: " + message)
                root.pendingAudioProfile = null
            }
            root.refreshAudioProfiles()
        }
    }
    Process {
        id: powerProc
        stderr: StdioCollector { id: powerStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.actionError = String(powerStderr.text || "Could not change Bluetooth power.").trim()
        }
    }

    component PolicyRow: PopupRow {
        required property string address
        shell: root.shell
        icon: "󰋋"
        title: "Audio on connect"
        detail: "Apply on the next connection"
        value: root.policyLabel(root.policyFor(address))
        active: root.policyFor(address) !== "manual"
        onClicked: root.stepPolicy(address, 1)
        function adjustKeyboard(direction) { root.stepPolicy(address, direction) }
    }

    component DeviceRow: Rectangle {
        id: row
        required property var dev
        required property string sectionName
        property bool cursored: false
        readonly property bool navigable: true
        property int actionIndex: -1
        readonly property var device: root.deviceByAddress(dev.address)
        readonly property var failure: root.actionFailure(dev.address)
        readonly property string pending: root.pendingAction(dev.address)
        readonly property string recovery: failure ? "retry"
            : pending === "pairing" && root.activeDeviceAction
                && Model.normalizedAddress(root.activeDeviceAction.address) === Model.normalizedAddress(dev.address)
                ? "cancel" : ""
        readonly property var sink: root.bluetoothAudioSink(dev)
        readonly property var source: root.bluetoothAudioSource(dev)
        readonly property var profiles: root.profileOptions(dev.address)
        readonly property var actions: {
            const values = []
            if (recovery) values.push(recovery)
            else if (dev.connected && sink) values.push("audio")
            values.push("details")
            if (!recovery && dev.connected && profiles.length > 1) values.push("profile")
            return values
        }
        readonly property string status: {
            if (failure) return String(failure.message || "Bluetooth operation failed")
            if (dev.blocked) return "Blocked"
            if (pending) return pending.charAt(0).toUpperCase() + pending.slice(1) + "…"
            if (dev.connected) {
                const values = []
                if (root.usingForAudio(dev)) values.push("Default audio")
                const codec = root.currentCodec(dev.address)
                if (codec) values.push(codec)
                if (dev.batteryAvailable) values.push(Math.round(dev.battery * 100) + "%")
                return values.join(" · ") || "Connected"
            }
            if (dev.paired || dev.bonded || dev.trusted) return "Paired"
            return dev.pairing ? "Pairing…" : ""
        }
        signal clicked(int button)
        onClicked: button => trigger(actionIndex >= 0 && actionIndex < actions.length ? actions[actionIndex] : "", button)
        onCursoredChanged: if (!cursored) actionIndex = -1

        function adjustKeyboard(direction) {
            if (!actions.length) return
            if (direction > 0 && actionIndex < actions.length - 1) actionIndex++
            else if (direction < 0 && actionIndex >= 0) actionIndex--
        }
        function trigger(action, button) {
            const live = row.device
            if (!live) return
            if (button === Qt.RightButton || action === "details") root.openDetails(live)
            else if (action === "retry") root.retryDevice(live)
            else if (action === "cancel") root.cancelPairing(live)
            else if (action === "audio") root.useDeviceForAudio(live)
            else if (action === "profile") root.openProfiles(live)
            else root.activateDevice(live)
        }

        implicitHeight: Math.max(Style.popupRowHeight, labels.implicitHeight + Style.controlPaddingY * 2)
        color: cursored ? root.shell.hoverFill()
            : dev.connected ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .2)
            : rowMouse.containsMouse ? root.shell.hoverFill() : "transparent"
        border.color: cursored ? root.shell.hoverEdge(.85)
            : dev.connected ? root.shell.alpha(root.shell.role("act_br", root.shell.accent), .5)
            : rowMouse.containsMouse ? root.shell.hoverEdge(.6) : "transparent"
        radius: root.shell.rounding

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: !!row.device && (!root.deviceActionBusy || row.recovery === "cancel")
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: event => row.trigger("", event.button)
        }
        Text {
            id: deviceIcon
            anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: Model.deviceIconGlyph(row.dev.icon,
                String(row.dev.name || "") + " " + String(row.dev.deviceName || ""), row.dev.connected)
            color: row.failure || row.dev.blocked ? root.shell.urgent : root.shell.foreground
            font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title + 3
        }
        Row {
            id: actionButtons
            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.xs
            Ui.PanelActionButton {
                visible: row.recovery !== ""
                size: Style.controlHeight; iconText: row.recovery === "cancel" ? "󰅙" : "󰑐"
                foreground: root.shell.foreground; hoverColor: row.recovery === "retry" ? root.shell.urgent : root.shell.foreground
                fontFamily: root.shell.iconGlyphFont
                hasCursor: row.cursored && row.actions[row.actionIndex] === row.recovery
                onClicked: row.trigger(row.recovery, Qt.LeftButton)
            }
            Ui.PanelActionButton {
                visible: row.recovery === "" && row.dev.connected && !!row.sink
                size: Style.controlHeight; iconText: root.usingForAudio(row.dev) ? "󰄬" : "󰓃"
                foreground: root.usingForAudio(row.dev) ? root.shell.accent : root.shell.foreground
                hoverColor: root.shell.foreground; fontFamily: root.shell.iconGlyphFont
                hasCursor: row.cursored && row.actions[row.actionIndex] === "audio"
                onClicked: row.trigger("audio", Qt.LeftButton)
            }
            Ui.PanelActionButton {
                size: Style.controlHeight; iconText: "󰒓"; foreground: root.shell.foreground
                hoverColor: root.shell.foreground; fontFamily: root.shell.iconGlyphFont
                hasCursor: row.cursored && row.actions[row.actionIndex] === "details"
                onClicked: row.trigger("details", Qt.LeftButton)
            }
            Ui.PanelActionButton {
                visible: row.recovery === "" && row.dev.connected && row.profiles.length > 1
                size: Style.controlHeight; iconText: "󰅀"; foreground: root.shell.foreground
                hoverColor: root.shell.foreground; fontFamily: root.shell.iconGlyphFont
                hasCursor: row.cursored && row.actions[row.actionIndex] === "profile"
                onClicked: row.trigger("profile", Qt.LeftButton)
            }
        }
        Column {
            id: labels
            anchors.left: deviceIcon.right; anchors.leftMargin: Style.controlPaddingX
            anchors.right: actionButtons.left; anchors.rightMargin: Style.sm
            anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text {
                width: parent.width; text: root.displayName(row.dev); textFormat: Text.PlainText
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.subtitle; font.bold: row.dev.connected; elide: Text.ElideRight
            }
            Text {
                visible: text !== ""; width: parent.width; text: row.status; textFormat: Text.PlainText
                color: row.failure || row.dev.blocked ? root.shell.urgent : root.shell.alpha(root.shell.foreground, .62)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight
            }
        }
    }

    Item {
        id: devicesPage
        anchors.fill: parent
        visible: root.page === "devices"
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero { shell: root.shell; title: "Bluetooth"; status: root.adapter ? root.adapter.enabled ? root.connectedDevices.length ? root.connectedDevices.length + " connected" : "scanning" : "turned off" : "no controller" }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"
                title: root.powerBusy ? "Changing Bluetooth power…" : root.adapter && root.adapter.enabled ? "Bluetooth powered" : "Bluetooth off"
                detail: root.adapter ? root.adapter.name : "No controller"
                active: root.adapter && root.adapter.enabled
                interactive: !!root.adapter && !root.powerBusy
                onClicked: root.togglePower()
            }
            Text {
                visible: root.actionError !== ""; width: parent.width
                text: root.actionError; textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.shell.urgent; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            PopupSeparator { shell: root.shell }
            Flickable {
                id: deviceScroll
                width: parent.width; height: parent.height - y
                contentWidth: width; contentHeight: deviceLists.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: deviceScroll.contentHeight > deviceScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Column {
                    id: deviceLists
                    width: deviceScroll.width; spacing: Style.rowGap
                    PopupSection { visible: root.connectedRows.length > 0; shell: root.shell; text: "CONNECTED" }
                    Repeater { model: root.connectedRows; DeviceRow { required property var modelData; dev: modelData; sectionName: "connected"; width: deviceLists.width } }
                    PopupSeparator { visible: root.connectedRows.length > 0 && root.knownRows.length > 0; shell: root.shell }
                    PopupSection { visible: root.knownRows.length > 0; shell: root.shell; text: "PAIRED" }
                    Repeater { model: root.knownRows; DeviceRow { required property var modelData; dev: modelData; sectionName: "known"; width: deviceLists.width } }
                    PopupSeparator { visible: (root.connectedRows.length || root.knownRows.length) && root.discoveredRows.length > 0; shell: root.shell }
                    PopupSection { visible: root.adapter && root.adapter.enabled; shell: root.shell; text: "AVAILABLE"; value: root.adapter && root.adapter.discovering ? "scanning" : "" }
                    Repeater { model: root.adapter && root.adapter.discovering ? root.discoveredRows : []; DeviceRow { required property var modelData; dev: modelData; sectionName: "discovered"; width: deviceLists.width } }
                    Text {
                        visible: !root.adapter || !root.adapter.enabled || !root.connectedRows.length && !root.knownRows.length && !root.discoveredRows.length
                        width: parent.width
                        text: !root.adapter ? "No Bluetooth controller" : !root.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices…"
                        color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily
                        font.pixelSize: Style.bodySmall; horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        visible: root.connectedRows.length + root.knownRows.length + root.discoveredRows.length > 0
                        width: parent.width; text: "j/k navigate  ·  h/l actions  ·  x forget  ·  right-click details"
                        color: root.shell.alpha(root.shell.foreground, .4); font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    Item {
        id: detailsPage
        anchors.fill: parent
        visible: root.page === "details" && !root.forgetConfirmation
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero { shell: root.shell; title: root.selectedRow ? root.displayName(root.selectedRow) : "Device"; status: "device details" }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.showDevices() }
            PopupSeparator { shell: root.shell }
            Flickable {
                id: detailsScroll
                width: parent.width; height: parent.height - y
                contentWidth: width; contentHeight: detailsColumn.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: detailsScroll.contentHeight > detailsScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Column {
                    id: detailsColumn
                    width: detailsScroll.width; spacing: Style.rowGap
                    PopupSection { shell: root.shell; text: "DEVICE" }
                    PopupRow {
                        visible: !root.renameEditing; width: parent.width; shell: root.shell
                        icon: "󰑕"; title: "Name"; detail: root.selectedRow ? root.displayName(root.selectedRow) : ""
                        interactive: !root.devicePropertyBusy; onClicked: root.beginRename()
                    }
                    TextField {
                        id: renameField
                        visible: root.renameEditing; width: parent.width; height: visible ? Style.px(38) : 0
                        maximumLength: 80; placeholderText: "Device name"
                        color: root.shell.foreground; placeholderTextColor: root.shell.alpha(root.shell.foreground, .35)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.body
                        onAccepted: root.commitRename()
                        Keys.onEscapePressed: { root.renameEditing = false; focus = false; Qt.callLater(root.resumeKeyboard) }
                        background: Rectangle {
                            color: root.shell.alpha(root.shell.foreground, .06)
                            border.color: root.shell.alpha(root.shell.foreground, renameField.activeFocus ? .5 : .22)
                            radius: root.shell.rounding
                        }
                    }
                    PolicyRow {
                        visible: root.selectedRow && root.isAudioDevice(root.selectedRow)
                        width: parent.width; address: root.selectedAddress
                    }
                    PopupSeparator { shell: root.shell }
                    PopupSection { shell: root.shell; text: "ACCESS" }
                    PopupRow {
                        width: parent.width; shell: root.shell; icon: root.selectedRow && root.selectedRow.trusted ? "󰌾" : "󰌿"
                        title: "Trusted"; detail: "Allow automatic reconnection"
                        value: root.selectedRow && root.selectedRow.trusted ? "On" : "Off"
                        active: root.selectedRow && root.selectedRow.trusted
                        interactive: !root.devicePropertyBusy; onClicked: root.toggleProperty("trusted")
                    }
                    PopupRow {
                        width: parent.width; shell: root.shell; icon: root.selectedRow && root.selectedRow.blocked ? "󰂭" : "󰂯"
                        title: "Blocked"; detail: "Prevent connections from this device"
                        value: root.selectedRow && root.selectedRow.blocked ? "On" : "Off"
                        active: root.selectedRow && root.selectedRow.blocked
                        interactive: !root.devicePropertyBusy; onClicked: root.toggleProperty("blocked")
                    }
                    PopupRow {
                        width: parent.width; shell: root.shell; icon: "󰒲"; title: "Allow wake"
                        detail: "Let supported devices wake the computer"
                        value: root.selectedRow && root.selectedRow.wakeAllowed ? "On" : "Off"
                        active: root.selectedRow && root.selectedRow.wakeAllowed
                        interactive: !root.devicePropertyBusy; onClicked: root.toggleProperty("wakeAllowed")
                    }
                    Text {
                        visible: root.devicePropertyBusy || root.propertyError !== ""
                        width: parent.width; text: root.devicePropertyBusy ? "Applying device setting…" : root.propertyError
                        textFormat: Text.PlainText; wrapMode: Text.WordWrap
                        color: root.propertyError ? root.shell.urgent : root.shell.alpha(root.shell.foreground, .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                    PopupSeparator { shell: root.shell }
                    PopupSection { shell: root.shell; text: "IDENTITY" }
                    PopupRow {
                        width: parent.width; shell: root.shell; icon: "󰘂"; title: "MAC address"
                        detail: root.selectedRow ? root.selectedRow.address : ""; interactive: false
                    }
                    PopupRow {
                        visible: root.selectedRow && (root.selectedRow.paired || root.selectedRow.bonded || root.selectedRow.trusted || root.selectedRow.connected || root.selectedRow.blocked)
                        width: parent.width; shell: root.shell; icon: "󰅙"; title: "Forget device"
                        detail: "Pairing will be required again"; titleColor: root.shell.urgent
                        interactive: !root.deviceActionBusy && !root.devicePropertyBusy
                        onClicked: root.forgetConfirmation = true
                    }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: root.page === "profiles"
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero { shell: root.shell; title: root.selectedRow ? root.displayName(root.selectedRow) : "Audio mode"; status: "bluetooth audio" }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.showDevices() }
            PopupRow {
                width: parent.width; shell: root.shell; icon: "󰓃"; title: "Use for audio now"
                detail: root.selectedRow && root.bluetoothAudioSource(root.selectedRow) ? "Output and microphone" : "Output"
                active: root.selectedRow && root.usingForAudio(root.selectedRow)
                interactive: !!root.selectedRow && !!root.bluetoothAudioSink(root.selectedRow)
                onClicked: if (root.selectedRow) root.useDeviceForAudio(root.selectedRow)
            }
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "AUDIO MODE"; value: root.audioProfileBusy ? "switching" : "" }
            ListView {
                width: parent.width; height: Math.min(contentHeight, parent.height - y - profileMessage.height - Style.rowGap)
                spacing: Style.rowGap; clip: true
                model: root.selectedRow ? root.profileOptions(root.selectedRow.address) : []
                delegate: PopupRow {
                    required property var modelData
                    width: ListView.view.width; shell: root.shell; icon: "󰎈"
                    title: modelData.label; detail: root.profileState(root.selectedAddress)
                        && root.profileState(root.selectedAddress).activeProfile === modelData.value ? "Active" : ""
                    active: root.profileState(root.selectedAddress)
                        && root.profileState(root.selectedAddress).activeProfile === modelData.value
                    interactive: !root.audioProfileBusy
                    onClicked: root.setAudioProfile(root.selectedAddress, modelData.value, "")
                }
            }
            Text {
                id: profileMessage
                width: parent.width
                text: root.profileError || (!root.profileOptions(root.selectedAddress).length ? "No switchable audio modes are currently available." : "Mode changes preserve volume and mute state.")
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.profileError ? root.shell.urgent : root.shell.alpha(root.shell.foreground, .48)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
        }
    }

    Item {
        anchors.fill: parent; z: 30
        visible: root.forgetConfirmation
        Rectangle { anchors.fill: parent; color: root.shell.alpha(root.background, .92) }
        Column {
            anchors.centerIn: parent; width: parent.width - Style.px(44); spacing: Style.sectionGap
            Text {
                width: parent.width
                text: "Forget “" + (root.selectedRow ? root.displayName(root.selectedRow) : "this device") + "”?\nYou will need to pair it again before reconnecting."
                textFormat: Text.PlainText; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title
            }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰜺"; title: "Cancel"; centerTitle: true; onClicked: root.forgetConfirmation = false }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰅙"; title: "Forget device"; centerTitle: true; titleColor: root.shell.urgent; onClicked: root.confirmForgetDevice() }
        }
    }
}

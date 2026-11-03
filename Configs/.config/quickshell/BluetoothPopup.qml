pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQml.Models
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import "Ui" as Ui
import "BluetoothModel.js" as Model

PopupCard {
    id: root
    readonly property int operationTimeoutMs: 45000
    readonly property int deviceStateTimeoutMs: 6000
    popupName: "bluetooth"
    keyboardHint: page === "devices" ? "↑↓ Scroll  Tab Move  ←→ Expand  Enter Connect  X Forget  Esc Close"
        : (page === "pair" ? "↑↓/Tab Move  Enter Pair" : "↑↓/Tab Move  ←→ Adjust  Enter Select") + "  Esc Back"
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
    readonly property var connectedRows: connectedDevices.map(Model.deviceSnapshot)
    readonly property var knownRows: knownDevices.map(Model.deviceSnapshot)
    readonly property var discoveredRows: discoveredDevices.map(Model.deviceSnapshot)
    readonly property var adapters: Bluetooth.adapters ? Bluetooth.adapters.values : []
    property var hardware: ({})
    property string hardwareError: ""
    property bool hardwareRefreshPending: false
    readonly property bool hardwareWanted: open && page === "devices"
    property bool showHiddenDevices: false
    property var expandedDevices: ({})
    readonly property var allMonitorDevices: Model.monitoringDevices(BluetoothMonitor.snapshot.devices || [], connectedRows.concat(knownRows), hardware)
    readonly property var shownMonitorDevices: allMonitorDevices.filter(device => !isMonitorHidden(device) || deviceConnected(device))
    readonly property var monitorDevices: showHiddenDevices ? allMonitorDevices : shownMonitorDevices
    readonly property int hiddenDeviceCount: allMonitorDevices.length - shownMonitorDevices.length
    readonly property int connectedCount: shownMonitorDevices.filter(device => deviceConnected(device)).length
    readonly property var connectedEntries: monitorDevices.filter(device => deviceConnected(device))
    readonly property var pairedEntries: monitorDevices.filter(device => !deviceConnected(device))
    readonly property var connectionLinks: Model.connectionLinks(adapters, monitorDevices, hardware, BluetoothMonitor.snapshot.receivers || [])
    readonly property bool showConnectionTree: connectionLinks.length > 1
    readonly property FontMetrics treeMetrics: FontMetrics { font.family: root.shell.fontFamily; font.pixelSize: Style.body }

    function isMonitorHidden(device) { return !!(BluetoothMonitor.snapshot.hidden || {})[Model.monitorKey(device)] }
    function treeLineColor(lit) { return lit ? root.shell.accent : root.shell.alpha(root.shell.foreground, Style.faintTextAlpha) }
    function deviceConnected(device) {
        const live = deviceByAddress(device.address)
        return live ? live.connected : !!device.connected
    }
    function toggleExpandedDevice(device) {
        const next = Model.cloneMap(expandedDevices)
        next[device.id] = !next[device.id]
        expandedDevices = next
        Qt.callLater(root.rebuildRows)
    }
    onMonitorDevicesChanged: Qt.callLater(root.rebuildRows)

    function refreshHardware() {
        if (!hardwareWanted) return
        if (hardwareProcess.running) hardwareRefreshPending = true
        else hardwareProcess.running = true
    }

    property string page: "devices"
    property string selectedAddress: ""
    property string devicePage: "devices"
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
    readonly property bool deviceActionBusy: deviceActionProcess.running
    readonly property bool devicePropertyBusy: propertyProcess.running
    readonly property bool audioProfileBusy: profileSetProcess.running
    readonly property bool powerBusy: powerProcess.running

    property var audioProfiles: ({})
    property bool audioProfilesRefreshPending: false
    property var pendingAudioProfile: null
    property var connectionStates: ({})
    property bool connectionBaselineReady: false
    property var policyQueue: ({})
    property bool owesDiscoveryStop: false
    readonly property bool scanWanted: open && page === "pair" && adapter && adapter.enabled

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
        return device ? Model.deviceSnapshot(device) : null
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
            label ? Number(deadline || Date.now() + operationTimeoutMs) : null)
    }
    function armActionDeadline() {
        actionDeadline.stop()
        const deadlines = Object.keys(pendingActions).filter(key => !(activeDeviceAction
            && Model.normalizedAddress(activeDeviceAction.address) === key && deviceActionBusy))
            .map(key => Number(pendingDeadlines[key] || 0))
        if (deadlines.length) {
            actionDeadline.interval = Math.max(0, Math.min(...deadlines) - Date.now())
            actionDeadline.start()
        }
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
                    && deviceActionProcess.running) continue
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
        if (!device || !device.address || deviceActionProcess.running || propertyProcess.running
                || profileSetProcess.running || pendingAction(device.address)) return
        const labels = { pair: "pairing", connect: "connecting", disconnect: "disconnecting", forget: "forgetting" }
        actionError = ""
        setActionFailure(device.address, "", "")
        setPending(device.address, labels[action], action)
        activeDeviceAction = { address: String(device.address), action: action }
        cancelRequested = false
        deviceActionProcess.command = ["hyprshell", "bluetooth/device-action", action, String(device.address)]
        deviceActionProcess.running = true
    }
    function activateDevice(device) {
        if (!device) return
        if (device.connected) runDeviceAction(device, "disconnect")
        else runDeviceAction(device, device.bonded ? "connect" : "pair")
    }
    function togglePower() {
        if (!adapter || powerBusy) return
        actionError = ""
        powerProcess.command = ["hyprshell", "bluetooth/power", adapter.enabled ? "off" : "on"]
        powerProcess.running = true
    }
    function cancelPairing(device) {
        if (!device || !activeDeviceAction || activeDeviceAction.action !== "pair"
                || Model.normalizedAddress(activeDeviceAction.address) !== Model.normalizedAddress(device.address)) return
        cancelRequested = true
        setPending(device.address, "", "")
        if (device.pairing) device.cancelPair()
        deviceActionProcess.signal(15)
    }

    function refreshAudioProfiles() {
        if (!connectedDevices.length && !Object.keys(policyQueue).length) return
        if (profilesProcess.running) audioProfilesRefreshPending = true
        else profilesProcess.running = true
    }
    function setAudioProfile(address, profile, policyKey) {
        if (!address || !profile || profileSetProcess.running || deviceActionProcess.running || propertyProcess.running) return false
        profileError = ""
        pendingAudioProfile = { address: Model.normalizedAddress(address), profile: String(profile), policyKey: String(policyKey || "") }
        profileSetProcess.command = ["hyprshell", "bluetooth/profile-set", String(address), String(profile)]
        profileSetProcess.running = true
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
        next[key] = { policy: policy, deadline: Date.now() + operationTimeoutMs, switchRequested: false }
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
        if (!popupEnabled || deviceActionProcess.running || propertyProcess.running || profileSetProcess.running) return
        const next = cloneMap(policyQueue)
        let changed = false
        for (const key in next) {
            const entry = cloneMap(next[key])
            const device = deviceByAddress(key)
            const policy = device ? policyFor(device.address) : "manual"
            if (!device || !device.connected || policy === "manual") { delete next[key]; changed = true; continue }
            entry.policy = policy
            if (Date.now() >= entry.deadline) { delete next[key]; changed = true; continue }
            const sink = bluetoothAudioSink(device)
            if (policy === "output") {
                if (sink) { useDeviceForAudio(device); delete next[key] }
                else next[key] = entry
                changed = true
                continue
            }

            const state = profileState(device.address)
            if (!state) continue
            const duplex = Model.duplexProfileOption(state)
            if (duplex && !Model.audioProfileHasInput(state, state.activeProfile)) {
                if (!entry.switchRequested && setAudioProfile(device.address, duplex.value, key)) {
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
    function armPolicyDeadline() {
        policyDeadline.stop()
        const deadlines = Object.values(policyQueue).map(entry => entry.deadline)
        if (deadlines.length) {
            policyDeadline.interval = Math.max(0, Math.min(...deadlines) - Date.now())
            policyDeadline.start()
        }
    }
    function expirePolicies() {
        for (const key in policyQueue)
            if (Date.now() >= policyQueue[key].deadline)
                removeQueuedPolicy(key, "Bluetooth audio did not become ready.")
    }
    function syncDiscovery() {
        if (!adapter) return
        if (scanWanted && !adapter.discovering) {
            owesDiscoveryStop = true
            adapter.discovering = true
        } else if (!scanWanted && owesDiscoveryStop && adapter.discovering) {
            adapter.discovering = false
        }
    }

    function openDetails(device) {
        if (!device) return
        devicePage = page
        selectedAddress = String(device.address || "")
        renameEditing = false
        propertyError = ""
        forgetConfirmation = false
        page = "details"
    }
    function openProfiles(device) {
        if (!device) return
        devicePage = page
        selectedAddress = String(device.address || "")
        profileError = ""
        page = "profiles"
        refreshAudioProfiles()
    }
    function showPage(nextPage) {
        renameEditing = false
        forgetConfirmation = false
        selectedAddress = ""
        page = nextPage
    }
    function beginRename() {
        if (!selectedRow || propertyProcess.running) return
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
        if (!selectedRow || !selectedRow.dbusPath || propertyProcess.running || deviceActionProcess.running) return
        propertyError = ""
        propertyProcess.propertyName = name
        propertyProcess.expected = expected
        propertyProcess.address = selectedRow.address
        propertyProcess.command = ["hyprshell", "bluetooth/device-property", name,
            String(selectedRow.dbusPath), String(value)]
        propertyProcess.running = true
    }
    function toggleProperty(name) {
        if (!selectedRow) return
        const next = !selectedRow[name]
        updateProperty(name, next ? "true" : "false", next)
    }
    function confirmForgetDevice() {
        const device = deviceByAddress(selectedAddress)
        forgetConfirmation = false
        showPage(devicePage)
        if (device) runDeviceAction(device, "forget")
    }
    function bumpDevices() {
        deviceRevision++
        BluetoothMonitor.refresh()
        syncPendingActions()
        observeConnections()
        Qt.callLater(root.applyPolicies)
        if (selectedAddress && !deviceByAddress(selectedAddress)) showPage(devicePage)
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
        if (event.key === Qt.Key_Escape && page !== "devices") { showPage(page === "pair" ? "devices" : devicePage); return true }
        if (page === "devices" && (event.key === Qt.Key_Up || event.key === Qt.Key_K
                || event.key === Qt.Key_Down || event.key === Qt.Key_J)) {
            devicesScroll.contentY = Math.max(0, Math.min(devicesScroll.contentHeight - devicesScroll.height,
                devicesScroll.contentY + (event.key === Qt.Key_Up || event.key === Qt.Key_K ? -1 : 1) * Style.popupRowHeight))
            return true
        }
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
            const live = row ? row.live : null
            if (live && (live.paired || live.bonded || live.trusted || live.connected)) {
                openDetails(live); forgetConfirmation = true
            }
            return true
        }
        return defaultKey(event)
    }

    onPageChanged: { clearCursor(); Qt.callLater(primeCursor) }
    onOpenChanged: {
        if (open) {
            showPage("devices")
            actionError = ""
            refreshAudioProfiles()
            Qt.callLater(primeCursor)
        } else {
            renameEditing = false
            forgetConfirmation = false
            showHiddenDevices = false
        }
    }
    onDevicesChanged: bumpDevices()
    onConnectedDevicesChanged: refreshAudioProfiles()
    onPipewireNodesChanged: Qt.callLater(root.applyPolicies)
    onAudioPoliciesChanged: Qt.callLater(root.applyPolicies)
    onPopupEnabledChanged: if (popupEnabled) Qt.callLater(root.applyPolicies)
    onPolicyQueueChanged: armPolicyDeadline()
    onPendingDeadlinesChanged: armActionDeadline()
    onDeviceActionBusyChanged: { armActionDeadline(); if (!deviceActionBusy) Qt.callLater(root.applyPolicies) }
    onDevicePropertyBusyChanged: if (!devicePropertyBusy) Qt.callLater(root.applyPolicies)
    onAudioProfileBusyChanged: if (!audioProfileBusy) Qt.callLater(root.applyPolicies)
    onScanWantedChanged: syncDiscovery()
    onAdapterChanged: syncDiscovery()
    onAdaptersChanged: refreshHardware()
    onHardwareWantedChanged: if (hardwareWanted) refreshHardware()

    Component.onCompleted: {
        BluetoothMonitor.users++
        initializeConnections()
    }
    Component.onDestruction: BluetoothMonitor.users--

    PwObjectTracker { objects: root.pipewireNodes.filter(node => node && node.audio) }
    Instantiator {
        model: root.pipewireNodes.filter(node => node && node.audio && !node.isStream)
        delegate: Connections {
            id: audioNodeWatcher
            required property var modelData
            target: audioNodeWatcher.modelData
            function onPropertiesChanged() { if (Object.keys(root.policyQueue).length) Qt.callLater(root.applyPolicies) }
            function onReadyChanged() { if (Object.keys(root.policyQueue).length) Qt.callLater(root.applyPolicies) }
        }
    }

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

    Connections {
        target: root.adapter
        ignoreUnknownSignals: true
        function onDiscoveringChanged() {
            if (!root.scanWanted && !root.adapter.discovering) root.owesDiscoveryStop = false
            root.syncDiscovery()
        }
        function onEnabledChanged() { root.syncDiscovery() }
    }
    Connections {
        target: AudioPorts
        function onCardsChanged() {
            if (root.open || Object.keys(root.policyQueue).length) root.refreshAudioProfiles()
        }
    }
    Timer { id: actionDeadline; onTriggered: { root.expirePendingActions(); root.armActionDeadline() } }
    Timer { id: policyDeadline; onTriggered: { root.expirePolicies(); root.armPolicyDeadline() } }

    Process {
        id: hardwareProcess
        command: ["python3", root.shell.home + "/.local/lib/hypr/bluetooth/connection-map.py"]
        stdout: StdioCollector { id: hardwareStdout; waitForEnd: true }
        stderr: StdioCollector { id: hardwareStderr; waitForEnd: true }
        onExited: code => {
            root.hardwareError = ""
            if (code !== 0) root.hardwareError = String(hardwareStderr.text || "Could not read connection hardware.").trim()
            else {
                try { root.hardware = JSON.parse(hardwareStdout.text) }
                catch (error) { root.hardwareError = "Connection hardware returned invalid data." }
            }
            if (root.hardwareRefreshPending) {
                root.hardwareRefreshPending = false
                Qt.callLater(root.refreshHardware)
            }
        }
    }
    Process {
        command: ["stdbuf", "-oL", "udevadm", "monitor", "--kernel", "--subsystem-match=bluetooth", "--subsystem-match=power_supply"]
        running: root.hardwareWanted
        stdout: SplitParser { onRead: line => { if (String(line).startsWith("KERNEL[")) root.refreshHardware() } }
    }

    Process {
        id: deviceActionProcess
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
                    operation.address, Date.now() + root.deviceStateTimeoutMs)
                root.syncPendingActions()
            }
        }
    }
    Process {
        id: propertyProcess
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
        id: profilesProcess
        command: ["bash", root.shell.home + "/.local/lib/hypr/bluetooth/profiles.sh"]
        onRunningChanged: if (!running && root.audioProfilesRefreshPending) {
            root.audioProfilesRefreshPending = false
            Qt.callLater(root.refreshAudioProfiles)
        }
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
                Qt.callLater(root.applyPolicies)
            } catch (error) { root.profileError = "Bluetooth audio returned invalid profile data." }
        }
    }
    Process {
        id: profileSetProcess
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
        id: powerProcess
        stderr: StdioCollector { id: powerStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.actionError = String(powerStderr.text || "Could not change Bluetooth power.").trim()
        }
    }

    component PowerRow: PopupRow {
        shell: root.shell
        icon: root.adapter && root.adapter.enabled ? "󰂯" : "󰂲"
        title: root.powerBusy ? "Changing Bluetooth power…" : root.adapter && root.adapter.enabled ? "Bluetooth powered" : "Bluetooth off"
        detail: root.adapter ? root.adapter.name : "No controller"
        active: root.adapter && root.adapter.enabled
        interactive: !!root.adapter && !root.powerBusy
        onClicked: root.togglePower()
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

    component AvailableDeviceRow: Rectangle {
        id: row
        required property var dev
        property bool cursored: false
        readonly property var live: root.deviceByAddress(dev.address)
        readonly property var failure: root.actionFailure(dev.address)
        readonly property string pending: root.pendingAction(dev.address)
        readonly property bool cancellable: pending === "pairing" && !!root.activeDeviceAction
            && Model.normalizedAddress(root.activeDeviceAction.address) === Model.normalizedAddress(dev.address)
        readonly property bool navigable: !!live && (!root.deviceActionBusy || cancellable)
        readonly property string status: failure ? String(failure.message || "Bluetooth operation failed")
            : dev.blocked ? "Blocked"
            : pending ? pending.charAt(0).toUpperCase() + pending.slice(1) + "…"
            : dev.pairing ? "Pairing…" : ""
        signal clicked(int button)
        onClicked: button => {
            if (button === Qt.RightButton) root.openDetails(live)
            else if (cancellable) root.cancelPairing(live)
            else root.activateDevice(live)
        }

        implicitHeight: Math.max(Style.popupRowHeight, labels.implicitHeight + Style.controlPaddingY * 2)
        color: cursored || rowMouse.containsMouse ? root.shell.hoverFill() : "transparent"
        radius: root.shell.rounding

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: row.navigable
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: event => row.clicked(event.button)
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
        Column {
            id: labels
            anchors.left: deviceIcon.right; anchors.leftMargin: Style.controlPaddingX
            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Text {
                width: parent.width; text: root.displayName(row.dev); textFormat: Text.PlainText
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.subtitle; elide: Text.ElideRight
            }
            Text {
                visible: text !== ""; width: parent.width; text: row.status; textFormat: Text.PlainText
                color: row.failure || row.dev.blocked ? root.shell.urgent : root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight
            }
        }
    }

    component TreeDashes: Item {
        id: dashes
        property bool lit
        property bool horizontal
        property bool junctionAtEnd
        property bool touchesFarEnd
        readonly property real length: horizontal ? width : height
        readonly property real gap: lit ? 0 : Style.xxs
        readonly property real targetDash: Math.round(root.treeMetrics.height) - gap
        readonly property real farGap: touchesFarEnd ? 0 : junctionAtEnd ? Math.ceil(gap / 2) : Math.floor(gap / 2)
        readonly property real span: length - farGap
        readonly property int fewerDashes: Math.max(1, Math.floor(span / (targetDash + gap)))
        readonly property int count: span <= gap ? 0
            : Math.abs(dashFor(fewerDashes) - targetDash) <= Math.abs(dashFor(fewerDashes + 1) - targetDash) ? fewerDashes : fewerDashes + 1
        readonly property real dash: dashFor(count)
        function dashFor(dashCount) { return dashCount ? (span - gap * dashCount) / dashCount : 0 }
        Repeater {
            model: dashes.count
            Rectangle {
                required property int index
                readonly property real start: Math.round(dashes.gap + index * (dashes.dash + dashes.gap))
                readonly property real end: Math.round(dashes.gap + index * (dashes.dash + dashes.gap) + dashes.dash)
                readonly property real along: dashes.junctionAtEnd ? dashes.length - end : start
                x: dashes.horizontal ? along : 0
                y: dashes.horizontal ? 0 : along
                width: dashes.horizontal ? end - start : dashes.width
                height: dashes.horizontal ? dashes.height : end - start
                color: root.treeLineColor(dashes.lit)
            }
        }
    }
    component TreeNode: Item {
        id: node
        property real stemX
        property real branchY
        property real lineTop
        property real lineBottom
        property bool hasDown
        property bool upLit
        property bool downLit
        property bool rightLit
        readonly property int lineWidth: 1
        readonly property int cellWidth: Math.round(root.treeMetrics.advanceWidth("│"))
        readonly property int cellHeight: Math.round(root.treeMetrics.height)
        readonly property int verticalArm: Math.floor((cellHeight - lineWidth) / 2)
        readonly property int horizontalArm: Math.floor((cellWidth - lineWidth) / 2)
        readonly property real lineX: Math.round(stemX - lineWidth / 2)
        readonly property real armY: Math.round(branchY - lineWidth / 2)
        readonly property real junctionTop: armY - verticalArm
        readonly property real junctionBottom: armY + lineWidth + verticalArm
        readonly property real cellRight: lineX + lineWidth + horizontalArm
        readonly property real childX: cellRight + cellWidth
        TreeDashes {
            x: node.lineX; y: node.lineTop
            width: node.lineWidth; height: node.junctionTop - y
            junctionAtEnd: true; lit: node.upLit
        }
        Rectangle {
            x: node.lineX; y: node.junctionTop
            width: node.lineWidth; height: node.armY + node.lineWidth - y
            color: root.treeLineColor(node.upLit)
        }
        Rectangle {
            visible: node.hasDown
            x: node.lineX; y: node.armY + node.lineWidth
            width: node.lineWidth; height: node.junctionBottom - y
            color: root.treeLineColor(node.downLit)
        }
        TreeDashes {
            visible: node.hasDown
            x: node.lineX; y: node.junctionBottom
            width: node.lineWidth; height: node.lineBottom - y
            lit: node.downLit
        }
        Rectangle {
            x: node.lineX + node.lineWidth; y: node.armY
            width: node.cellRight - x; height: node.lineWidth
            color: root.treeLineColor(node.rightLit)
        }
        TreeDashes {
            horizontal: true; touchesFarEnd: true
            x: node.cellRight; y: node.armY
            width: node.childX - x; height: node.lineWidth
            lit: node.rightLit
        }
    }
    component DeviceCard: BluetoothDeviceCard {
        id: deviceCard
        readonly property var live: root.deviceByAddress(device.address)
        readonly property string pending: root.pendingAction(device.address)
        readonly property var failure: root.actionFailure(device.address)
        readonly property bool cancellable: pending === "pairing" && !!root.activeDeviceAction
            && Model.normalizedAddress(root.activeDeviceAction.address) === Model.normalizedAddress(device.address)
        readonly property var sink: connected && live ? root.bluetoothAudioSink(live) : null
        readonly property var profiles: connected && live ? root.profileOptions(device.address) : []
        readonly property bool canChooseAudioMode: profiles.length > 1
        readonly property bool canToggleHidden: hiddenDevice || !connected
        shell: root.shell
        hasActions: !!sink || canChooseAudioMode || canToggleHidden || !!live
        connected: live ? live.connected : !!device.connected
        blocked: live ? live.blocked : !!device.blocked
        connectable: !!live && (cancellable || !pending && !root.deviceActionBusy && !root.devicePropertyBusy && !root.audioProfileBusy)
        pendingText: pending ? pending + "…" : ""
        failureText: failure ? String(failure.message || "Bluetooth operation failed") : ""
        audioStatus: [sink && root.usingForAudio(live) ? "Default audio" : "", connected ? root.currentCodec(device.address) : ""].filter(Boolean).join(" · ")
        hiddenDevice: root.isMonitorHidden(device)
        expanded: root.expandedDevices[device.id] === true
        settingsEnabled: BluetoothMonitor.ready
        onExpandedToggled: root.toggleExpandedDevice(device)
        onSettingChanged: (key, value) => BluetoothMonitor.send({cmd: "set", device: device.id, key: key, value: value})
        onConnectionToggled: cancellable ? root.cancelPairing(live) : root.activateDevice(live)
        onDetailsRequested: root.openDetails(live)
        PopupRow {
            visible: !!deviceCard.sink
            width: parent.width; shell: root.shell; icon: "󰓃"; title: "Use for audio"
            detail: root.bluetoothAudioSource(deviceCard.live) ? "Output and microphone" : "Output"
            active: root.usingForAudio(deviceCard.live)
            onClicked: root.useDeviceForAudio(deviceCard.live)
        }
        PopupRow {
            visible: deviceCard.canChooseAudioMode
            width: parent.width; shell: root.shell; icon: "󰎈"; title: "Audio mode"
            value: root.currentCodec(deviceCard.device.address)
            onClicked: root.openProfiles(deviceCard.live)
        }
        PopupRow {
            visible: deviceCard.canToggleHidden
            width: parent.width; shell: root.shell
            icon: deviceCard.hiddenDevice ? "󰈈" : "󰈉"; title: deviceCard.hiddenDevice ? "Show in list" : "Hide from list"
            interactive: BluetoothMonitor.ready
            onClicked: {
                BluetoothMonitor.send({cmd: "hide", key: Model.monitorKey(deviceCard.device), value: !deviceCard.hiddenDevice})
                root.resumeKeyboard()
            }
        }
        PopupRow {
            visible: !!deviceCard.live
            width: parent.width; shell: root.shell; icon: "󰒓"; title: "Details"; value: "󰁔"
            onClicked: root.openDetails(deviceCard.live)
        }
    }

    Item {
        visible: root.page === "devices"
        anchors.fill: parent
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            Item {
                width: parent.width; height: monitorHero.implicitHeight
                PopupHero {
                    id: monitorHero
                    width: parent.width - hiddenToggle.width - (hiddenToggle.visible ? Style.md : 0); shell: root.shell; title: "Bluetooth"
                    status: root.connectedCount + " connected"
                }
                Ui.Button {
                    id: hiddenToggle
                    anchors.right: parent.right; anchors.top: parent.top
                    visible: root.hiddenDeviceCount > 0 || root.showHiddenDevices
                    width: visible ? implicitWidth : 0
                    readonly property bool navigable: visible
                    property bool cursored: false
                    text: (root.showHiddenDevices ? "󰈉" : "󰈈") + (!root.showHiddenDevices && root.hiddenDeviceCount ? " " + root.hiddenDeviceCount : "")
                    selected: root.showHiddenDevices || cursored; bordered: true
                    foreground: root.shell.foreground; fontFamily: root.shell.iconGlyphFont; fontSize: Style.caption
                    horizontalPadding: Style.sm; verticalPadding: Style.xxs
                    ToolTip.visible: hiddenHover.hovered; ToolTip.delay: Style.tooltipDelay
                    ToolTip.text: root.showHiddenDevices ? "Hide hidden devices" : "Show hidden devices (" + root.hiddenDeviceCount + ")"
                    HoverHandler { id: hiddenHover }
                    onClicked: root.showHiddenDevices = !root.showHiddenDevices
                }
            }
            PowerRow { width: parent.width }
            PopupRow {
                width: parent.width; shell: root.shell; title: "Pair new device"; value: "󰁔"
                onClicked: root.showPage("pair")
            }
            PopupRow {
                visible: (BluetoothMonitor.snapshot.denied || []).length > 0
                width: parent.width; shell: root.shell; icon: "󰌾"; title: "Allow Logitech access"
                detail: "Enable pointer, wheel and Fn-key settings"
                onClicked: { root.shell.closePopup(); root.shell.run(["pkexec", root.shell.home + "/.local/lib/hypr/bluetooth/allow-access.sh"]) }
            }
            PopupHint {
                shell: root.shell; error: true
                width: parent.width; text: root.actionError
            }
            PopupSeparator { shell: root.shell }
            PopupHint {
                shell: root.shell; error: true
                width: parent.width; text: root.hardwareError || BluetoothMonitor.error
            }
            Flickable {
                id: devicesScroll
                width: parent.width; height: parent.height - y
                contentWidth: width; contentHeight: deviceList.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: Ui.PanelScrollBar { policy: devicesScroll.contentHeight > devicesScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Column {
                    id: deviceList
                    width: devicesScroll.width; spacing: Style.rowGap
                    Column {
                        visible: !root.showConnectionTree && root.connectedEntries.length > 0
                        width: parent.width; spacing: Style.sm
                        PopupSection { shell: root.shell; text: "CONNECTED" }
                        Repeater {
                            model: root.showConnectionTree ? [] : root.connectedEntries
                            DeviceCard { required property var modelData; device: modelData; width: deviceList.width }
                        }
                    }
                    Column {
                        visible: !root.showConnectionTree && root.pairedEntries.length > 0
                        width: parent.width; spacing: Style.sm
                        PopupSection { shell: root.shell; text: "PAIRED" }
                        Repeater {
                            model: root.showConnectionTree ? [] : root.pairedEntries
                            DeviceCard { required property var modelData; device: modelData; width: deviceList.width }
                        }
                    }
                    Text {
                        visible: !root.showConnectionTree && !root.monitorDevices.length; width: parent.width
                        text: root.adapters.length ? "No paired devices" : "No Bluetooth controller"
                        color: root.shell.mutedText; font.family: root.shell.fontFamily
                        font.pixelSize: Style.bodySmall; horizontalAlignment: Text.AlignHCenter
                    }
                    PopupSection { visible: root.showConnectionTree; shell: root.shell; text: "CONNECTIONS" }
                    Item {
                        visible: root.showConnectionTree
                        width: parent.width; height: Style.controlHeight
                        Rectangle {
                            id: pcBadge
                            width: Style.controlHeight; height: width; radius: root.shell.rounding
                            color: root.shell.accent
                            Text {
                                anchors.centerIn: parent; text: "󰍹"; color: root.shell.background
                                font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title
                            }
                        }
                        Text {
                            anchors.left: pcBadge.right; anchors.leftMargin: Style.controlPaddingX
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "This PC" + (root.hardware.host ? " · " + root.hardware.host : "")
                            textFormat: Text.PlainText; elide: Text.ElideRight
                            color: root.shell.foreground; font.family: root.shell.fontFamily
                            font.pixelSize: Style.subtitle; font.bold: true
                        }
                    }
                    Repeater {
                        id: linkRows
                        readonly property int lastLiveIndex: root.connectionLinks.reduce((last, link, index) => link.online > 0 ? index : last, -1)
                        model: root.showConnectionTree ? root.connectionLinks : []
                        delegate: Item {
                            id: linkRow
                            required property var modelData
                            required property int index
                            readonly property bool live: modelData.online > 0
                            readonly property color lineColor: live ? root.shell.accent : root.shell.mutedText
                            readonly property real trunkX: Style.controlHeight / 2
                            width: deviceList.width
                            height: linkColumn.implicitHeight
                            TreeNode {
                                id: trunkNode
                                stemX: linkRow.trunkX; branchY: linkHead.height / 2
                                lineTop: linkRow.index === 0 ? -deviceList.spacing : -deviceList.spacing / 2; lineBottom: linkRow.height + deviceList.spacing / 2
                                hasDown: linkRow.index < root.connectionLinks.length - 1
                                upLit: linkRow.index <= linkRows.lastLiveIndex
                                downLit: linkRow.index < linkRows.lastLiveIndex
                                rightLit: linkRow.live
                            }
                            Column {
                                id: linkColumn
                                x: trunkNode.childX
                                width: linkRow.width - x; spacing: Style.sm
                                Item {
                                    id: linkHead
                                    width: parent.width
                                    height: Math.max(adapterBadge.height, adapterLabels.implicitHeight)
                                    Rectangle {
                                        id: adapterBadge
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Style.controlHeight; height: width; radius: root.shell.rounding
                                        color: linkRow.live ? root.shell.selectedFill() : "transparent"
                                        border.color: linkRow.lineColor
                                        Text {
                                            anchors.centerIn: parent; text: Model.connectionIcon(linkRow.modelData.type); color: linkRow.lineColor
                                            font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title
                                        }
                                    }
                                    Column {
                                        id: adapterLabels
                                        anchors.left: adapterBadge.right; anchors.leftMargin: Style.md
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.xxs
                                        Text {
                                            width: parent.width; text: linkRow.modelData.label
                                            textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                            color: linkRow.lineColor; font.family: root.shell.fontFamily
                                            font.pixelSize: Style.bodySmall; font.bold: true
                                        }
                                        Text {
                                            visible: !!text; width: parent.width; text: linkRow.modelData.detail
                                            textFormat: Text.PlainText; wrapMode: Text.WordWrap
                                            color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                        }
                                        Text {
                                            visible: !linkRow.modelData.enabled; text: "Turned off"
                                            color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                        }
                                    }
                                }
                                Repeater {
                                    id: linkDevices
                                    readonly property int lastConnectedIndex: linkRow.modelData.devices.reduce((last, device, index) => root.deviceConnected(device) ? index : last, -1)
                                    model: linkRow.modelData.devices
                                    delegate: Item {
                                        id: deviceSlot
                                        required property var modelData
                                        required property int index
                                        readonly property real stemX: adapterBadge.width / 2
                                        readonly property real stemTop: linkColumn.spacing + (index === 0 ? (linkHead.height - adapterBadge.height) / 2 : 0)
                                        width: linkColumn.width; height: slotCard.height
                                        TreeNode {
                                            id: slotNode
                                            stemX: deviceSlot.stemX; branchY: deviceSlot.height / 2
                                            lineTop: deviceSlot.index === 0 ? -deviceSlot.stemTop : -linkColumn.spacing / 2; lineBottom: deviceSlot.height + linkColumn.spacing / 2
                                            hasDown: deviceSlot.index < linkDevices.count - 1
                                            upLit: deviceSlot.index <= linkDevices.lastConnectedIndex
                                            downLit: deviceSlot.index < linkDevices.lastConnectedIndex
                                            rightLit: slotCard.connected
                                        }
                                        DeviceCard {
                                            id: slotCard
                                            x: slotNode.childX
                                            width: deviceSlot.width - x
                                            device: deviceSlot.modelData
                                        }
                                    }
                                }
                                Text {
                                    visible: linkRow.modelData.devices.length === 0; width: parent.width
                                    text: "No paired devices"; wrapMode: Text.WordWrap
                                    color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                                }
                            }
                        }
                    }
                    Text {
                        visible: root.showConnectionTree && root.adapters.length === 0; width: parent.width
                        text: "No Bluetooth controller"; color: root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                }
            }
        }
    }

    Item {
        visible: root.page === "pair"
        anchors.fill: parent
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero {
                shell: root.shell; title: "Pair new device"
                status: root.adapter ? root.adapter.enabled ? "scanning" : "turned off" : "no controller"
            }
            PowerRow { width: parent.width }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.showPage("devices") }
            PopupHint {
                shell: root.shell; error: true
                width: parent.width; text: root.actionError
            }
            PopupSeparator { shell: root.shell }
            Flickable {
                id: pairScroll
                width: parent.width; height: parent.height - y
                contentWidth: width; contentHeight: availableList.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: Ui.PanelScrollBar { policy: pairScroll.contentHeight > pairScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Column {
                    id: availableList
                    width: pairScroll.width; spacing: Style.sm
                    PopupSection { visible: root.adapter && root.adapter.enabled; shell: root.shell; text: "AVAILABLE"; value: root.adapter && root.adapter.discovering ? "scanning" : "" }
                    Repeater {
                        model: root.scanWanted && root.adapter.discovering ? root.discoveredRows : []
                        AvailableDeviceRow { required property var modelData; dev: modelData; width: availableList.width }
                    }
                    Text {
                        visible: !root.adapter || !root.adapter.enabled || !root.discoveredRows.length
                        width: parent.width
                        text: !root.adapter ? "No Bluetooth controller" : !root.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices…"
                        color: root.shell.mutedText; font.family: root.shell.fontFamily
                        font.pixelSize: Style.bodySmall; horizontalAlignment: Text.AlignHCenter
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
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.showPage(root.devicePage) }
            PopupSeparator { shell: root.shell }
            Flickable {
                id: detailsScroll
                width: parent.width; height: parent.height - y
                contentWidth: width; contentHeight: detailsColumn.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: Ui.PanelScrollBar { policy: detailsScroll.contentHeight > detailsScroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
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
                    PopupHint {
                        shell: root.shell; error: root.propertyError !== ""
                        visible: root.devicePropertyBusy || root.propertyError !== ""
                        width: parent.width; text: root.devicePropertyBusy ? "Applying device setting…" : root.propertyError
                        wrapMode: Text.Wrap; horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Style.bodySmall
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
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.showPage(root.devicePage) }
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
                width: parent.width; height: Math.min(contentHeight, parent.height - y - profileMessage.height - parent.spacing)
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
            PopupHint {
                id: profileMessage
                shell: root.shell; error: root.profileError !== ""
                width: parent.width
                text: root.profileError || (!root.profileOptions(root.selectedAddress).length ? "No switchable audio modes are currently available." : "Mode changes preserve volume and mute state.")
                wrapMode: Text.Wrap; horizontalAlignment: Text.AlignLeft
                font.pixelSize: Style.bodySmall
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

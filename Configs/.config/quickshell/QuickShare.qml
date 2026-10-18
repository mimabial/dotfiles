pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var shell
    readonly property string binary: shell.home + "/.local/bin/quickshare"
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || shell.home + "/.config") + "/quickshare"
    readonly property int receiveSeconds: 120
    readonly property int previewSeconds: 8
    property var snapshot: ({})
    property bool online: false
    property string error: ""
    property int pending: 0
    property bool picking: false
    property var selectedFiles: []
    property string selectedPeer: ""
    property string highlightedTransfer: ""
    property bool effectsEnabled: false
    property var effectsAnchorWindow: null
    property var effectsAnchorItem: null
    property var effectsPreview: null
    readonly property bool busy: pending > 0
    readonly property var devices: snapshot.devices || []
    readonly property var transfers: snapshot.transfers || []
    readonly property bool discoverable: online && snapshot.visible === true
    readonly property int activeTransfers: transfers.filter(transfer => !terminal(transfer.state)).length
    readonly property int requests: transfers.filter(transfer => transfer.state === "waiting_acceptance").length
    readonly property int remainingSeconds: discoverable ? Math.max(0, Number(snapshot.visibility_expires_at) - Math.floor(clock.date.getTime() / 1000)) : 0
    readonly property alias transferModel: transferRows

    function terminal(state) { return ["completed", "rejected", "cancelled", "failed"].includes(state) }
    function stateLabel(state) {
        return ({connecting: "Connecting", authenticating: "Verifying", waiting_acceptance: "Waiting for approval", negotiating: "Negotiating connection", transferring: "Transferring", completed: "Completed", rejected: "Rejected", cancelled: "Cancelled", failed: "Failed"})[state] || state
    }
    function medium(transport) {
        return ({lan: "Local network", bluetooth: "Bluetooth", hotspot: "Direct Wi-Fi"})[transport] || "Transport unconfirmed"
    }
    function acceptSnapshot(data) {
        if (data.online === false) { online = false; error = data.error; return }
        if (data.version !== 1 || !data.instance_id) return
        if (snapshot.instance_id === data.instance_id && snapshot.revision >= data.revision) return
        snapshot = data
        online = true
        const rows = transfers.slice().reverse().sort((a, b) => (a.state === "waiting_acceptance" ? 0 : terminal(a.state) ? 2 : 1) - (b.state === "waiting_acceptance" ? 0 : terminal(b.state) ? 2 : 1))
        for (let i = 0; i < rows.length; ++i) {
            let found = i
            while (found < transferRows.count && transferRows.get(found).transferId !== rows[i].id) ++found
            if (found === transferRows.count) transferRows.insert(i, {transferId: rows[i].id, transferData: rows[i]})
            else if (found > i) transferRows.move(found, i, 1)
            transferRows.setProperty(i, "transferData", rows[i])
        }
        if (transferRows.count > rows.length) transferRows.remove(rows.length, transferRows.count - rows.length)
        if (!devices.some(device => device.id === selectedPeer)) selectedPeer = devices.length === 1 ? devices[0].id : ""
    }
    function run(args, input, finished) {
        const process = job.createObject(root, {command: [binary].concat(args), input: input || ""})
        process.exited.connect(code => {
            --pending
            if (code) error = process.stderr.text.trim() || "quickshare exited with " + code
            else if (finished) {
                try { finished(process.stdout.text) } catch (failure) { error = String(failure) }
            }
            process.destroy()
        })
        error = ""
        ++pending
        process.running = true
    }
    function reconnect() { error = ""; if (!watch.running) watch.running = true }
    function pickFiles() {
        picking = true
        run(["pick-files"], "", output => {
            const paths = JSON.parse(output)
            if (paths.length) { selectedFiles = paths; show() }
        })
    }
    function show() { shell.popupCenteredName = "quickshare"; shell.popupName = "quickshare" }
    function takeShare(token) { run(["take-share", token], "", output => { selectedFiles = JSON.parse(output); show() }) }
    function send() { run(["send", selectedPeer], JSON.stringify(selectedFiles), () => { selectedFiles = [] }) }
    function visibility() { run(["visible", String(discoverable ? 0 : receiveSeconds)]) }
    function directory(path) { run(["download-dir"], JSON.stringify(path)) }
    function setEffects(value) { effectsEnabled = value; effectsFile.setText(value ? "on\n" : "off\n") }
    function previewEffects() {
        effectsPreview = {id: "preview", direction: "outbound", state: "transferring", transport: "lan"}
        previewEnd.restart()
    }

    ListModel { id: transferRows; dynamicRoles: true }
    SystemClock { id: clock; precision: SystemClock.Seconds; enabled: root.discoverable }
    Timer { id: previewEnd; interval: root.previewSeconds * 1000; onTriggered: root.effectsPreview = null }
    Component {
        id: job
        Process {
            id: process
            property string input: ""
            stdinEnabled: input !== ""
            onStarted: { if (input) write(input); stdinEnabled = false }
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    Process {
        id: watch
        command: [root.binary, "watch"]
        running: true
        stdout: SplitParser { onRead: data => { try { root.acceptSnapshot(JSON.parse(data)) } catch (failure) { root.error = String(failure) } } }
        stderr: StdioCollector {}
        onExited: code => { root.online = false; if (code) root.error = stderr.text.trim() }
    }
    Process {
        command: [root.binary, "browse"]
        running: root.shell.popupName === "quickshare"
        stdinEnabled: true
    }
    onPendingChanged: if (!busy) picking = false
    FileView {
        id: effectsFile
        path: root.configDir + "/transfer-effects"; printErrors: false; watchChanges: true; atomicWrites: true
        onLoaded: root.effectsEnabled = text().trim() === "on"
        onFileChanged: reload()
    }
    QuickShareEffects {
        shell: root.shell
        enabled: root.effectsEnabled
        connected: root.online
        transfers: root.transfers
        preview: root.effectsPreview
        anchorWindow: root.effectsAnchorWindow
        anchorItem: root.effectsAnchorItem
    }
    IpcHandler {
        target: "quickshare"
        function open(): void { root.show() }
        function share(token: string): void { root.takeShare(token) }
        function transfer(id: string): void { root.highlightedTransfer = id; root.show() }
    }
}

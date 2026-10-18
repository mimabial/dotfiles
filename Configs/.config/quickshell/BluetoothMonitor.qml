pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int users: 0
    property var snapshot: ({phase: "starting", devices: [], receivers: [], hidden: {}})
    property bool refreshPending: false
    readonly property bool ready: snapshot.phase !== "starting" && snapshot.phase !== "error"
    readonly property string error: snapshot.error || ""

    function send(message) {
        if (process.processId) process.write(JSON.stringify(message) + "\n")
    }
    function refresh() {
        if (users < 1) return
        if (!process.running) process.running = true
        else if (ready) send({cmd: "refresh"})
        else refreshPending = true
    }

    Process {
        id: process
        command: ["python3", "-B", Quickshell.env("HOME") + "/.local/lib/hypr/bluetooth/monitor.py"]
        running: root.users > 0
        stdinEnabled: true
        stderr: StdioCollector { id: errors; waitForEnd: true }
        stdout: SplitParser {
            onRead: line => {
                try { root.snapshot = JSON.parse(line) }
                catch (error) { console.warn("Bluetooth monitor: " + error) }
                if (root.refreshPending) {
                    root.refreshPending = false
                    root.refresh()
                }
            }
        }
        onStarted: root.snapshot = {phase: "starting", devices: [], receivers: [], hidden: {}}
        onExited: code => {
            if (root.users > 0) root.snapshot = Object.assign({}, root.snapshot, {
                phase: "error", error: String(errors.text || "Bluetooth monitor stopped (" + code + ").").trim()
            })
        }
    }
}

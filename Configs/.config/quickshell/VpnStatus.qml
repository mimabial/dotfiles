pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var output: ({ text: "", tooltip: "" })
    property bool refreshPending: false

    function refresh() {
        if (snapshot.running) refreshPending = true
        else snapshot.running = true
    }
    property Process snapshot: Process {
        command: [Quickshell.env("HOME") + "/.local/lib/hypr/quickshell/vpn.sh"]
        running: true
        stdout: SplitParser { onRead: line => root.output = JSON.parse(line) }
        onExited: if (root.refreshPending) { root.refreshPending = false; root.refresh() }
    }
    property Process tunnelEvents: Process {
        command: ["mullvad", "status", "listen"]
        running: true
        stdout: SplitParser { onRead: root.refresh() }
    }
    property Process networkEvents: Process {
        command: ["ip", "monitor", "link", "address", "route"]
        running: true
        stdout: SplitParser { onRead: root.refresh() }
    }
}

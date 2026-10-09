pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string archiveDirectory: Quickshell.env("HOME") + "/.local/state/hypr/notifications/"
    property var report: ({ entries: [], unread: 0, seen: 0, paused: false })
    property bool refreshPending: false
    function refresh() {
        if (history.running) refreshPending = true
        else history.running = true
    }
    FileView {
        path: root.archiveDirectory + "archive.jsonl"; watchChanges: true; printErrors: false
        onFileChanged: root.refresh()
    }
    FileView {
        path: root.archiveDirectory + "seen"; watchChanges: true; printErrors: false
        onFileChanged: root.refresh()
    }
    Process {
        id: history
        running: true
        command: [Quickshell.env("HOME") + "/.local/lib/hypr/notify/history.sh"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) }
            catch (error) { console.warn("notification history: " + error) }
        } }
        onExited: if (root.refreshPending) { root.refreshPending = false; root.refresh() }
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.Notifications"]
        stdout: SplitParser { onRead: line => { if (line.includes("PropertiesChanged") || line.includes("NotificationClosed")) root.refresh() } }
    }
}

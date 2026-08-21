import QtQuick
import Quickshell
import Quickshell.Io

// Bar entry for AI coding subscriptions. Strictly a display: hyprshell
// system/agent-usage emits one record per agent and this draws what appears.
BarButton {
    id: root
    property bool popupEnabled: true
    property var records: []
    property int selected: 0
    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    readonly property var headline: {
        let best = null
        for (const record of records)
            for (const limit of (record.limits || []))
                if (Number(limit.percent) >= 0 && (!best || Number(limit.percent) > Number(best.percent))) best = limit
        return best
    }
    readonly property bool alarming: headline !== null && Number(headline.percent) >= 0.9

    css: "custom-agents"
    visible: records.length > 0
    text: "󱚣"
    textColor: alarming ? shell.role("error", shell.foreground) : shell.role("c9", shell.foreground)
    onClicked: shell.togglePopup("agents")

    function refresh() { if (!collect.running) collect.running = true }

    // Display half: paint from the cache immediately, and repaint when the
    // producer rewrites it. Never blocks on a collector.
    FileView {
        path: Quickshell.env("HOME") + "/.cache/hypr/agents/usage.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.records = JSON.parse(text()) || [] }
            catch (error) { root.records = [] }
        }
    }
    // Producer half: a ~20s scan, run detached from anything the UI waits on.
    Process { id: collect; command: ["hyprshell", "system/agent-usage", "--write"] }
    Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    AgentsPopup {
        id: panel
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        records: root.records; selected: root.selected
        onSelect: index => root.selected = index
    }
}

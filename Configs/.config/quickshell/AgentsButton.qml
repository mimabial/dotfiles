import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: root
    property bool popupEnabled: true
    property var records: []
    property int selected: 0
    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    readonly property var alarmRecord: records.find(record => String(record.id) === panel.recommendationId) || provider
    readonly property var headline: {
        let best = null
        for (const limit of (alarmRecord && alarmRecord.limits || []))
            if (Number(limit.percent) >= 0 && (!best || Number(limit.percent) > Number(best.percent))) best = limit
        return best
    }
    readonly property bool alarming: headline !== null && Number(headline.percent) >= 0.9

    css: "agents"
    readonly property bool shown: records.length > 0
    text: "󱚣"
    // `alarm` is the style's channel for the >=90% state; both states fall back
    // to their own role when the rule leaves them out.
    textColor: alarming
        ? (box.alarm !== undefined ? styleColor("alarm") : shell.role("error", shell.foreground))
        : box.content !== undefined ? styleColor("content")
        : shell.role("c9", shell.foreground)
    onClicked: shell.togglePopup("agents")

    function refresh(force) {
        if (collect.running) return
        collect.command = force
            ? ["hyprshell", "system/agent-usage", "--write", "--force"]
            : ["hyprshell", "system/agent-usage", "--write"]
        collect.running = true
    }

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
        onRefreshRequested: root.refresh(true)
    }
}

import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: root
    property bool popupEnabled: true
    property var records: []
    property int selected: 0
    readonly property real highestUsage: {
        let highest = 0
        for (const record of records)
            for (const limit of (record.limits || []))
                highest = Math.max(highest, Number(limit.percent) || 0)
        return highest
    }
    readonly property bool alarming: highestUsage >= panel.alarmUsage
    readonly property bool exhausted: highestUsage >= 1

    css: "agents"
    readonly property bool shown: records.length > 0
    text: exhausted ? "󱚢" : alarming ? "󱚞" : "󱚠"
    onClicked: shell.togglePopup("agents")
    onRecordsChanged: reportLimits()

    function reportLimits() {
        if (!panel.notifyLimit) return
        const now = Date.now()
        for (const record of records) {
            const observedAt = Number(record.limitsObservedAt)
            if (!isFinite(observedAt) || observedAt <= 0 || now - observedAt > panel.staleAfterMs) continue
            for (const limit of (record.limits || [])) {
                const usage = Number(limit.percent), resetAt = Date.parse(limit.resetsAt)
                if (!isFinite(usage) || usage < 0 || isFinite(resetAt) && resetAt <= now) continue
                shell.run(["hyprshell", "system/agent-limit-alert", String(record.id),
                    String(record.name || record.id), String(limit.label || "Limit"),
                    String(Math.floor(usage * 1000)), String(limit.resetsAt || ""), String(observedAt)])
            }
        }
    }

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
        onLimitNotificationsEnabled: root.reportLimits()
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Units.js" as Units

Singleton {
    id: root
    property int consumers: 0
    property var records: []
    property var notificationSettings: ({notifyRecommendation: false, notifyLimit: false})
    readonly property bool notifyLimit: notificationSettings.notifyLimit === true
    readonly property int staleAfterMs: 40 * Units.MS_PER_MINUTE
    readonly property string home: Quickshell.env("HOME")
    readonly property string usageScript: home + "/.local/lib/hypr/system/agent-usage.sh"
    onRecordsChanged: reportLimits()
    onNotifyLimitChanged: if (notifyLimit) reportLimits()

    function reportLimits() {
        if (!notifyLimit) return
        const now = Date.now()
        for (const record of records) {
            const observedAt = Number(record.limitsObservedAt)
            if (!isFinite(observedAt) || observedAt <= 0 || now - observedAt > staleAfterMs) continue
            for (const limit of (record.limits || [])) {
                const usage = Number(limit.usageFraction), resetAt = Date.parse(limit.resetsAt)
                if (!isFinite(usage) || usage < 0 || isFinite(resetAt) && resetAt <= now) continue
                Quickshell.execDetached(["hyprshell", "system/agent-limit-alert", String(record.id),
                    String(record.name || record.id), String(limit.label || "Limit"),
                    String(Math.floor(usage * 1000)), String(limit.resetsAt || ""), String(observedAt)])
            }
        }
    }

    function refresh(force) {
        if (usageCollector.running) return
        usageCollector.command = force
            ? ["bash", usageScript, "--write", "--force"]
            : ["bash", usageScript, "--write"]
        usageCollector.running = true
    }

    function setNotification(key, enabled) {
        const next = Object.assign({}, notificationSettings, {[key]: enabled})
        notificationSettingsFile.setText(JSON.stringify(next, null, 2) + "\n")
        notificationSettings = next
    }

    FileView {
        path: root.home + "/.cache/hypr/agents/usage.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.records = JSON.parse(text()) || [] }
            catch (error) { root.records = [] }
        }
    }
    FileView {
        id: notificationSettingsFile
        path: root.home + "/.config/quickshell/agents.json"
        watchChanges: true; atomicWrites: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.notificationSettings = {
                    notifyRecommendation: saved.notifyRecommendation === true,
                    notifyLimit: saved.notifyLimit === true
                }
            } catch (error) { root.notificationSettings = ({notifyRecommendation: false, notifyLimit: false}) }
        }
    }
    Process { id: usageCollector }
    Timer { interval: 15 * Units.MS_PER_MINUTE; running: root.consumers > 0; repeat: true; triggeredOnStart: true; onTriggered: root.refresh(false) }
}

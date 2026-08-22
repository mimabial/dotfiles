import QtQuick
import Quickshell.Io

ScriptButton {
    id: root
    css: "updates"
    command: ["hyprshell", "system/system.update.sh"]
    interval: 86400000
    fallback: "󰮯"
    textColor: shell.role("c9", shell.foreground)
    property bool popupEnabled: true
    // the vertical bars have room to stack the total under the glyph
    property bool showCount: false
    readonly property int pending: {
        const groups = output.packages || ({})
        let total = 0
        for (const key in groups) total += (groups[key] || []).length
        return total
    }
    readonly property bool stacked: showCount && pending > 0
    text: stacked
        ? "\u{f0baf}<br><span style='color:" + shell.foreground + "'>" + pending + "</span>"
        : "\u{f0baf}"
    textFormat: stacked ? Text.RichText : Text.PlainText
    onClicked: shell.togglePopup("updates")
    // the daily poll leaves the report a day stale; opening the panel re-reads
    // it, which is a cache hit inside the script's own 15 min TTL
    refreshKey: shell.popupName === "updates"

    // the forced check writes the cache the module reads, so re-run the module
    // when it exits rather than guessing at how long it took
    property Process recheckProc: Process {
        command: ["hyprshell", "system/system.update.sh", "--refresh"]
        onRunningChanged: if (!running) root.refresh(0)
    }

    UpdatesPopup {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        report: root.output; checking: root.recheckProc.running
        onRecheck: root.recheckProc.running = true
    }
}

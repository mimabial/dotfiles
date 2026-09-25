import QtQuick
import Quickshell.Io

ScriptButton {
    id: root
    css: "updates"
    tooltip: ""
    command: ["hyprshell", "system/system.update.sh"]
    indicator: "updates"
    interval: 86400000
    fallback: ""
    property bool popupEnabled: true
    property bool hideWhenCurrent: true
    // the vertical bars have room to stack the total under the glyph
    property bool showCount: false
    readonly property int pending: {
        const groups = output.packages || ({})
        let total = 0
        for (const key in groups) total += (groups[key] || []).length
        return total
    }
    readonly property bool hasErrors: (output.errors || []).length > 0
    readonly property bool shown: !hideWhenCurrent || pending > 0 || hasErrors
    visible: shown
    readonly property bool stacked: showCount && pending > 0
    text: stacked
        ? "<br><span style='color:" + shell.foreground + "'>" + pending + "</span>"
        : ""
    textFormat: stacked ? Text.RichText : Text.PlainText
    // a host can claim either button for its own action; unclaimed, the left
    // one opens the report and the right one does nothing
    property var primaryAction: null
    property var rightAction: null
    onClicked: button => button === Qt.RightButton && root.rightAction ? root.rightAction()
        : root.primaryAction ? root.primaryAction()
        : root.shell.togglePopup("updates")
    // the daily poll leaves the report stale; opening the panel re-reads it,
    // usually from the provider's six-hour cache
    refreshKey: shell.popupName === "updates"

    // the forced check writes the cache the module reads, so re-run the module
    // when it exits rather than guessing at how long it took
    property Process recheckProc: Process {
        command: ["hyprshell", "system/system.update.sh", "--refresh"]
        onRunningChanged: if (!running) root.refresh()
    }

    UpdatesPopup {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        report: root.output; checking: root.recheckProc.running
        onRecheck: root.recheckProc.running = true
    }
}

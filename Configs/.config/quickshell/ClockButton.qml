import QtQuick

BarButton {
    id: root
    property string kind: "main"
    property bool popupEnabled: true
    property bool timerPopup: false
    readonly property bool timing: timerPopup && (shell.activeTimers.length > 0 || shell.stopwatch.running)
    readonly property int timingSeconds: shell.activeTimers.length ? Math.max(0, Number(shell.activeTimers[0].epoch) - shell.timerNow) : Math.floor(shell.stopwatchMs / 1000)
    readonly property var formats: kind === "main" ? ["HH\n—\nmm", "h\n—\nmm\nAP", "dd\nMMM\n''yy", "HH\nmm"]
        : kind === "winbar" ? ["HH:mm\ndd|MM", "dd|MM\nHH:mm", "ddd dd\nHH:mm", "HH:mm"]
        : ["dddd HH:mm", "dddd h:mm AP", "HH:mm", "h:mm AP", "ddd d MMM HH:mm", "ddd d MMM h:mm AP", "d MMMM yyyy", "yyyy-MM-dd HH:mm"]
    readonly property int index: shell.store[kind + "Clock"] % formats.length
    text: timing ? statusText(timingSeconds) : Qt.formatDateTime(shell.clock.date, timerPopup ? "HH\nmm" : formats[index])
    smoothTextColor: !timing
    textColor: timerPopup ? timing ? shell.alpha(shell.role("c3", shell.accent), blink.phase) : shell.accent : shell.foreground
    SequentialAnimation {
        id: blink; property real phase: 1; running: root.timing; loops: Animation.Infinite; onStopped: phase = 1
        NumberAnimation { target: blink; property: "phase"; from: .35; to: 1; duration: 500 }
        NumberAnimation { target: blink; property: "phase"; from: 1; to: .35; duration: 500 }
    }
    function statusText(seconds) { const long = seconds >= 6000, high = Math.floor(seconds / (long ? 3600 : 60)), low = Math.floor(seconds / (long ? 60 : 1)) % 60; return String(high).padStart(2, "0") + "\n" + String(low).padStart(2, "0") }
    onClicked: button => {
        if (timerPopup && button !== Qt.MiddleButton) shell.togglePopup("timer")
        else if (button === Qt.RightButton) shell.store[kind + "Clock"] = (shell.store[kind + "Clock"] + 1) % formats.length
        else if (button === Qt.MiddleButton) {
            shell.closePopup()
            shell.run(["hyprshell", "launch/tui", "--app-id", "org.tui.timezone", "--title", "Timezone", "--", "hyprshell", "system/timezone"])
        } else shell.togglePopup("clock")
    }

    ClockPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && !root.timerPopup }
    AlarmTimerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.timerPopup; entries: root.shell.activeTimers; now: root.shell.timerNow; stopwatch: root.shell.stopwatch; stopwatchMs: root.shell.stopwatchMs; onStopwatchAction: action => root.shell.controlStopwatch(action); onChanged: root.shell.refreshTimers() }
}

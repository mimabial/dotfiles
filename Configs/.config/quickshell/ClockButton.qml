import QtQuick
import "ClockFormats.js" as ClockFormats
import "Units.js" as Units

BarButton {
    id: root
    property string kind: "top"
    property bool popupEnabled: true
    property bool timerPopup: false
    property string popupName: "clock"
    property string calendarPopupName: "clock"
    readonly property bool timing: timerPopup && (shell.activeTimers.length > 0 || shell.clockwork.active)
    readonly property int timingSeconds: shell.activeTimers.length ? Math.max(0, Number(shell.activeTimers[0].epoch) - shell.timerNow) : 0
    readonly property string timingText: shell.activeTimers.length ? statusText(timingSeconds)
        : shell.clockwork.active ? verticalTime(shell.clockwork.barTimeText) : statusText(timingSeconds)
    readonly property var formats: ClockFormats.forKind(kind)
    readonly property var selectedFormat: ClockFormats.selected(kind, shell.prefs[kind + "Clock"])
    text: timing ? timingText : Qt.formatDateTime(shell.clock.date, timerPopup ? "HH\nmm" : selectedFormat.pattern)
    smoothTextColor: !timing
    textColor: timerPopup ? timing ? shell.alpha(shell.role("c3", shell.accent), blink.phase) : shell.accent : shell.foreground
    SequentialAnimation {
        id: blink; property real phase: 1; running: root.timing; loops: Animation.Infinite; onStopped: phase = 1
        NumberAnimation { target: blink; property: "phase"; from: .35; to: 1; duration: 500 }
        NumberAnimation { target: blink; property: "phase"; from: 1; to: .35; duration: 500 }
    }
    function statusText(seconds) {
        const pad = value => String(value).padStart(2, "0")
        const minutes = Math.floor(seconds / Units.SECONDS_PER_MINUTE), minutesFitTwoDigits = minutes < 100
        return minutesFitTwoDigits ? pad(minutes) + "\n" + pad(Math.floor(seconds) % Units.SECONDS_PER_MINUTE)
            : pad(Math.floor(seconds / Units.SECONDS_PER_HOUR)) + "\n" + pad(minutes % 60)
    }
    function verticalTime(value) {
        const parts = String(value || "00:00").split(":")
        return parts.length > 2 ? parts[0] + ":" + parts[1] + "\n" + parts[2] : parts[0] + "\n" + parts[1]
    }
    onClicked: button => {
        if (timerPopup && button !== Qt.MiddleButton) shell.togglePopup("timer")
        else if (button === Qt.RightButton) shell.prefs[kind + "Clock"] = (shell.prefs[kind + "Clock"] + 1) % formats.length
        else if (button === Qt.MiddleButton) {
            shell.closePopup()
            shell.run(["hyprshell", "launch/tui", "--app-id", "org.tui.timezone", "--title", "Timezone", "--", "hyprshell", "system/timezone"])
        } else shell.togglePopup(popupName)
    }

    ClockPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && !root.timerPopup; popupName: root.calendarPopupName }
    AlarmTimerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.timerPopup; entries: root.shell.activeEntries; now: root.shell.timerNow; onChanged: root.shell.refreshTimers() }
}

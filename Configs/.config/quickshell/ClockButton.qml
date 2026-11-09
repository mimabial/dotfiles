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
    readonly property bool timing: timerPopup && (shell.alarmTimers.timers.length > 0 || shell.clockwork.active)
    readonly property int timingSeconds: shell.alarmTimers.timers.length ? Math.max(0, Number(shell.alarmTimers.timers[0].epoch) - shell.alarmTimers.now) : 0
    readonly property string timingText: shell.alarmTimers.timers.length ? statusText(timingSeconds)
        : shell.clockwork.active ? verticalTime(shell.clockwork.barTimeText) : statusText(timingSeconds)
    readonly property var formats: ClockFormats.forKind(kind)
    readonly property var selectedFormat: ClockFormats.selected(kind, shell.prefs[kind + "Clock"])
    property color idleColor: shell.foreground
    readonly property var announcement: shell.upcomingEvents.announcement
    readonly property bool announcing: !timerPopup && !selectedFormat.pattern.includes("\n") && announcement.text !== ""
    readonly property color phaseColor: announcement.phase === "live" ? shell.role("error", shell.accent) : shell.accent
    readonly property string announcementMarkup: "  <font color=\"" + shell.faintText + "\">│</font>  <font color=\"" + phaseColor + "\">●</font> "
        + "<font color=\"" + (announcement.phase === "soon" ? shell.foreground : phaseColor) + "\">"
        + announcement.text.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>"
    text: timing ? timingText : Qt.formatDateTime(shell.clock.date, timerPopup ? "HH\nmm" : selectedFormat.pattern)
        + (announcing ? announcementMarkup : "")
    textFormat: announcing ? Text.StyledText : Text.AutoText
    smoothTextColor: !timing
    textColor: timerPopup ? timing ? shell.alpha(shell.role("c3", shell.accent), blink.phase) : shell.accent : idleColor
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
    AlarmTimerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.timerPopup; entries: root.shell.alarmTimers.entries; now: root.shell.alarmTimers.now; onChanged: root.shell.alarmTimers.refresh() }
}

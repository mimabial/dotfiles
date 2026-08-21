import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

PopupCard {
    id: root
    popupName: "timer"
    contentWidth: 360
    contentHeight: timerColumn.implicitHeight + padding * 2
    property var entries: []
    property int now: Math.floor(Date.now() / 1000)
    property var stopwatch: ({elapsed: 0, started: 0, running: false, laps: []})
    property real stopwatchMs: 0
    property string mode: "timer"
    property string error: ""
    signal changed
    signal stopwatchAction(string action)

    function duration() { return Number(hoursField.text || 0) * 3600 + Number(minutesField.text || 0) * 60 + Number(secondsField.text || 0) }
    function setDuration(seconds) { seconds = Math.max(0, Math.min(359999, Math.floor(seconds))); hoursField.text = String(Math.floor(seconds / 3600)).padStart(2, "0"); minutesField.text = String(Math.floor(seconds / 60) % 60).padStart(2, "0"); secondsField.text = String(seconds % 60).padStart(2, "0"); error = "" }
    function addDuration(seconds) { setDuration(duration() + seconds) }
    function alarmTarget() {
        if (!alarmHours.acceptableInput || !alarmMinutes.acceptableInput) return null
        const target = new Date(); target.setHours(Number(alarmHours.text), Number(alarmMinutes.text), 0, 0)
        if (target.getTime() <= Date.now()) target.setDate(target.getDate() + 1)
        return target
    }
    function timerWhen() { const seconds = duration(); if (!seconds) return ""; const today = shell.clock.date.toDateString(), target = new Date(Date.now() + seconds * 1000); return "Rings " + (target.toDateString() === today ? "today" : Qt.formatDate(target, "ddd d MMM")) + " at " + Qt.formatTime(target, "HH:mm:ss") }
    function run(args) {
        error = ""
        const process = actionComponent.createObject(root)
        process.command = [shell.home + "/.local/lib/hypr/calendar/alarm-timer.sh"].concat(args)
        process.running = true
    }
    function addTimer(seconds, label) {
        if (seconds < 1) { error = "Set a duration above zero"; return }
        run(["add", "timer", String(Math.floor(Date.now() / 1000) + seconds), String(label || timerLabel.text).trim() || "Timer"])
        timerLabel.text = ""
    }
    function addAlarm() {
        const target = alarmTarget()
        if (!target) { error = "Use a 24-hour time like 07:30"; return }
        run(["add", "alarm", String(Math.floor(target.getTime() / 1000)), String(alarmLabel.text).trim() || "Alarm"])
        alarmLabel.text = ""
    }
    function remaining(epoch) {
        const seconds = Math.max(0, Number(epoch) - now), hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60)
        return (hours ? hours + ":" : "") + String(minutes).padStart(hours ? 2 : 1, "0") + ":" + String(seconds % 60).padStart(2, "0")
    }
    function elapsed(milliseconds) {
        const seconds = Math.floor(milliseconds / 1000), hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60)
        return (hours ? String(hours).padStart(2, "0") + ":" : "") + String(minutes).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0") + "." + Math.floor(milliseconds / 100) % 10
    }

    component Field: TextField {
        height: Style.controlHeight; leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX; topPadding: 0; bottomPadding: 0
        color: root.shell.foreground; placeholderTextColor: root.shell.alpha(root.shell.foreground, .35)
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        background: Rectangle { radius: root.shell.rounding; color: root.shell.alpha(root.shell.foreground, .06); border.width: 1; border.color: root.shell.alpha(root.shell.foreground, parent.activeFocus ? .45 : .18) }
    }
    component NumberField: Field {
        id: field; property int maximum: 59; property var submit: () => root.addTimer(root.duration(), ""); width: 44; text: "00"; horizontalAlignment: TextInput.AlignHCenter; inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: field.maximum }
        onActiveFocusChanged: if (activeFocus) selectAll()
        onEditingFinished: text = String(Number(text) || 0).padStart(2, "0")
        onAccepted: submit()
    }
    component TimeMark: Text { width: 52; height: Style.bodySmall; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    component ModeTab: BarButton {
        property bool selected: false
        active: false; radius: shell.rounding; fill: "transparent"; outline: "transparent"; textColor: selected ? shell.accent : shell.alpha(shell.foreground, .6)
    }
    component PresetButton: BarButton { radius: shell.rounding; fill: shell.alpha(shell.accent, .18); outline: "transparent"; textColor: shell.accent }
    property Component actionComponent: Component { Process {
        id: action; property string failure: ""
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: action.failure = String(text).trim() }
        onExited: (code, status) => { if (code !== 0) root.error = failure || "Could not schedule alarm"; root.changed(); destroy() }
    } }

    Column {
        id: timerColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        PopupSection { shell: root.shell; text: "TIME TOOLS" }
        Row {
            width: parent.width; spacing: Style.sm
            ModeTab { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: "TIMER"; selected: root.mode === "timer"; onClicked: root.mode = "timer" }
            ModeTab { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: "ALARM"; selected: root.mode === "alarm"; onClicked: root.mode = "alarm" }
            ModeTab { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: "STOPWATCH"; selected: root.mode === "stopwatch"; onClicked: root.mode = "stopwatch" }
        }
        PopupSeparator { shell: root.shell }
        StackLayout { id: pages; width: parent.width; currentIndex: root.mode === "timer" ? 0 : root.mode === "alarm" ? 1 : 2
            Column { width: pages.width; spacing: Style.sectionGap
                Column { width: parent.width; spacing: Style.xs
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.sm
                        NumberField { id: hoursField; width: 52; height: Style.controlHeight + Style.sm; maximum: 99; font.pixelSize: Style.title }
                        TimeMark { width: 9; height: Style.controlHeight + Style.sm; text: ":"; font.pixelSize: Style.title }
                        NumberField { id: minutesField; width: 52; height: Style.controlHeight + Style.sm; font.pixelSize: Style.title }
                        TimeMark { width: 9; height: Style.controlHeight + Style.sm; text: ":"; font.pixelSize: Style.title }
                        NumberField { id: secondsField; width: 52; height: Style.controlHeight + Style.sm; font.pixelSize: Style.title }
                    }
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.sm
                        TimeMark { text: "H" } TimeMark { width: 9 } TimeMark { text: "M" } TimeMark { width: 9 } TimeMark { text: "S" }
                    }
                }
                Grid { width: parent.width; columns: 3; spacing: Style.sm
                    Repeater { model: [{text:"+1m", seconds:60}, {text:"+5m", seconds:300}, {text:"+10m", seconds:600}, {text:"+15m", seconds:900}, {text:"+30m", seconds:1800}, {text:"+1h", seconds:3600}]
                        PresetButton { required property var modelData; width: (pages.width - Style.sm * 2) / 3; height: Style.controlHeight; shell: root.shell; text: modelData.text; onClicked: root.addDuration(modelData.seconds) }
                    }
                }
                Text { visible: root.duration() > 0; width: parent.width; height: Style.controlHeight; text: root.timerWhen(); color: root.shell.alpha(root.shell.foreground, .65); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                Field { id: timerLabel; width: parent.width; placeholderText: "Label (optional)" }
                Row { width: parent.width; spacing: Style.sm
                    BarButton { id: resetTimer; width: (pages.width - Style.sm * 2) / 3; height: Style.controlHeight; shell: root.shell; radius: shell.rounding; fill: shell.alpha(shell.foreground, .06); outline: shell.alpha(shell.foreground, .18); text: "RESET"; onClicked: root.setDuration(0) }
                    BarButton { width: parent.width - resetTimer.width - parent.spacing; height: Style.controlHeight; shell: root.shell; text: "START"; active: true; onClicked: root.addTimer(root.duration(), "") }
                }
            }
            Column { width: pages.width; spacing: Style.sectionGap
                Column { width: parent.width; spacing: Style.xs
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.sm
                        NumberField { id: alarmHours; width: 52; height: Style.controlHeight + Style.sm; maximum: 23; font.pixelSize: Style.title; text: Qt.formatTime(new Date(Date.now() + 3600000), "HH"); submit: () => root.addAlarm() }
                        TimeMark { width: 9; height: Style.controlHeight + Style.sm; text: ":"; font.pixelSize: Style.title }
                        NumberField { id: alarmMinutes; width: 52; height: Style.controlHeight + Style.sm; font.pixelSize: Style.title; text: Qt.formatTime(new Date(Date.now() + 3600000), "mm"); submit: () => root.addAlarm() }
                    }
                    Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.sm
                        TimeMark { text: "H" } TimeMark { width: 9 } TimeMark { text: "M" }
                    }
                }
                Field { id: alarmLabel; width: parent.width; placeholderText: "Label (optional)" }
                BarButton { width: parent.width; height: Style.controlHeight; shell: root.shell; text: "SET ALARM"; active: true; onClicked: root.addAlarm() }
            }
            Column { width: pages.width; spacing: Style.sm
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.elapsed(root.stopwatchMs); color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 28; font.bold: true }
                Row { width: parent.width; spacing: Style.sm
                    BarButton { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: "RESET"; enabled: root.stopwatchMs > 0; opacity: enabled ? 1 : .4; onClicked: root.stopwatchAction("reset") }
                    BarButton { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: "LAP"; enabled: root.stopwatch.running; opacity: enabled ? 1 : .4; onClicked: root.stopwatchAction("lap") }
                    BarButton { width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight; shell: root.shell; text: root.stopwatch.running ? "PAUSE" : "START"; active: true; onClicked: root.stopwatchAction("toggle") }
                }
                ListView { visible: root.stopwatch.laps && root.stopwatch.laps.length > 0; width: parent.width; height: Math.min(contentHeight, 100); spacing: Style.xs; clip: true; model: (root.stopwatch.laps || []).slice().reverse()
                    delegate: PopupRow { required property var modelData; required property int index; width: ListView.view.width; shell: root.shell; title: "Lap " + (root.stopwatch.laps.length - index); value: root.elapsed(modelData) }
                }
            }
        }
        Text { visible: root.error !== ""; width: parent.width; text: root.error; color: root.shell.role("error", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "ACTIVE · " + root.entries.length }
        Text { visible: root.entries.length === 0; width: parent.width; text: "No active alarms or timers"; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        ListView {
            visible: root.entries.length > 0; width: parent.width; height: Math.min(contentHeight, 180); spacing: Style.sm; clip: true; model: root.entries
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: modelData.kind === "alarm" ? "󰀠" : "󰔛"; title: modelData.label || (modelData.kind === "alarm" ? "Alarm" : "Timer"); detail: (modelData.kind === "alarm" ? Qt.formatDateTime(new Date(modelData.epoch * 1000), "ddd HH:mm") : "Ends " + Qt.formatTime(new Date(modelData.epoch * 1000), "HH:mm")) + " · click to cancel"; value: root.remaining(modelData.epoch); active: true; onClicked: root.run(["cancel", String(modelData.id)]) }
        }
    }
}

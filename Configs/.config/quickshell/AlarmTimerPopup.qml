pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

PopupCard {
    id: root
    popupName: "timer"
    contentWidth: Style.px(400)
    contentHeight: timerColumn.implicitHeight + padding * 2
    property var entries: []
    property int now: Math.floor(Date.now() / 1000)
    property int timerHours: 0
    property int timerMinutes: 0
    property int timerSeconds: 0
    readonly property date alarmDefault: new Date(Date.now() + 3600000)
    property int alarmHours: alarmDefault.getHours()
    property int alarmMinutes: alarmDefault.getMinutes()
    property var alarmDays: [alarmDefault.getDay()]
    property string mode: "timer"
    property string error: ""
    readonly property var clockwork: shell.clockwork
    readonly property var alarmWeekdays: [
        {text: "S", name: "Sun", day: 0}, {text: "M", name: "Mon", day: 1},
        {text: "T", name: "Tue", day: 2}, {text: "W", name: "Wed", day: 3},
        {text: "T", name: "Thu", day: 4}, {text: "F", name: "Fri", day: 5},
        {text: "S", name: "Sat", day: 6}
    ]
    readonly property var primaryModes: [
        {mode: "timer", text: "TIMER"}, {mode: "alarm", text: "ALARM"},
        {mode: "stopwatch", text: "STOPWATCH"}
    ]
    readonly property var secondaryModes: [
        {mode: "countdown", text: "COUNTDOWN"}, {mode: "intervals", text: "INTERVALS"},
        {mode: "pomodoro", text: "POMODORO"}
    ]
    signal changed

    function primeCursor() {
        rebuildRows()
        cursorIndex = navigableRows.length > 0 ? 0 : -1
    }
    onOpenChanged: {
        wantsKeyboard = false
        if (open) Qt.callLater(primeCursor)
        else clearCursor()
    }

    function duration() { return timerHours * 3600 + timerMinutes * 60 + timerSeconds }
    function setDuration(seconds) {
        seconds = Math.max(0, Math.min(359999, Math.floor(seconds)))
        timerHours = Math.floor(seconds / 3600)
        timerMinutes = Math.floor(seconds / 60) % 60
        timerSeconds = seconds % 60
        error = ""
    }
    function addDuration(seconds) { setDuration(duration() + seconds) }
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
    function alarmDaySelected(day) { return alarmDays.indexOf(day) !== -1 }
    function toggleAlarmDay(day) {
        alarmDays = alarmDaySelected(day)
            ? alarmDays.filter(selected => selected !== day)
            : alarmDays.concat([day]).sort((left, right) => left - right)
        error = ""
    }
    function alarmTargets() {
        const targets = [], current = new Date()
        for (const day of alarmDays) {
            const target = new Date(current)
            target.setHours(alarmHours, alarmMinutes, 0, 0)
            target.setDate(target.getDate() + (day - current.getDay() + 7) % 7)
            if (target.getTime() <= current.getTime()) target.setDate(target.getDate() + 7)
            targets.push(target)
        }
        return targets.sort((left, right) => left.getTime() - right.getTime())
    }
    function alarmWhen() {
        if (alarmDays.length === 0) return "Select at least one day"
        const names = alarmWeekdays.filter(item => alarmDaySelected(item.day)).map(item => item.name)
        return "Rings " + names.join(", ") + " at " + String(alarmHours).padStart(2, "0") + ":" + String(alarmMinutes).padStart(2, "0")
    }
    function addAlarm() {
        const targets = alarmTargets()
        if (targets.length === 0) { error = "Select at least one day"; return }
        const label = String(alarmLabel.text).trim() || "Alarm"
        for (const target of targets)
            run(["add", "alarm", String(Math.floor(target.getTime() / 1000)), label])
        alarmLabel.text = ""
    }
    function resetAlarm() {
        const target = new Date(Date.now() + 3600000)
        alarmHours = target.getHours(); alarmMinutes = target.getMinutes()
        alarmDays = [target.getDay()]
        alarmLabel.text = ""; error = ""
    }
    function remaining(epoch) {
        const seconds = Math.max(0, Number(epoch) - now), hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60)
        return (hours ? hours + ":" : "") + String(minutes).padStart(hours ? 2 : 1, "0") + ":" + String(seconds % 60).padStart(2, "0")
    }
    function selectMode(nextMode) {
        if (clockwork.running && mode !== nextMode) return
        if (nextMode !== "timer" && nextMode !== "alarm") {
            clockwork.selectMode(nextMode)
        }
        mode = nextMode
        clearCursor()
        Qt.callLater(primeCursor)
    }
    function heroStatus() {
        const kind = mode === "timer" ? "timer" : mode === "alarm" ? "alarm" : ""
        if (kind !== "") {
            const count = entries.filter(item => item.kind === kind).length
            return (kind === "timer" ? "Timer" : "Alarm") + " · " + (count > 0 ? count + " scheduled" : "Ready")
        }
        return clockwork.modeName + " · " + clockwork.statusText
    }
    function hintText() {
        const reset = "R\u00a0reset", modes = "1–6\u00a0change\u00a0mode"
        const edit = "J/K\u00a0move     H/L\u00a0adjust     Enter\u00a0edit"
        if (mode === "timer") return edit + "     Space\u00a0start     " + reset + "     " + modes
        if (mode === "alarm") return edit + "     Space\u00a0add     " + reset + "     " + modes
        if (mode === "stopwatch") {
            if (clockwork.running) return "Space\u00a0pause     L\u00a0lap     " + reset
            if (clockwork.completed) return "Space\u00a0start\u00a0again     " + reset + "     " + modes
            return (clockwork.storedElapsedMs > 0 ? "Space\u00a0resume" : "Space\u00a0start")
                + "     " + reset + "     " + modes
        }
        if (clockwork.running) return mode === "pomodoro"
            ? "Space\u00a0pause     S\u00a0skip     " + reset
            : "Space\u00a0pause     " + reset
        if (clockwork.completed) return "Space\u00a0start\u00a0again     " + reset + "     " + modes
        if (mode === "pomodoro" && clockwork.pomodoroSessionStarted)
            return "Space\u00a0resume     S\u00a0skip     " + reset + "     " + modes
        if (mode === "intervals") return edit + "     "
            + (clockwork.storedElapsedMs > 0 ? "Space\u00a0resume" : "Space\u00a0start")
            + "     " + reset + "     " + modes
        if (clockwork.storedElapsedMs > 0)
            return "Space\u00a0resume     " + reset + "     " + modes
        return edit + "     Space\u00a0start     " + reset + "     " + modes
    }
    function startClockwork() {
        clockwork.startPause()
    }
    function resetClockwork() { clockwork.reset() }
    function adjustCursor(direction) {
        rebuildRows()
        if (cursorIndex < 0 && navigableRows.length > 0) cursorIndex = 0
        if (cursorIndex < 0 || cursorIndex >= navigableRows.length) return false
        const item = navigableRows[cursorIndex]
        if (!item.adjustKeyboard) return false
        item.adjustKeyboard(direction)
        return true
    }
    function handleKey(event) {
        if (wantsKeyboard) return false
        const shortcuts = ["timer", "alarm", "stopwatch", "countdown", "intervals", "pomodoro"]
        if (event.text >= "1" && event.text <= "6") {
            selectMode(shortcuts[Number(event.text) - 1])
            return true
        }
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { moveCursor(1); return true }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { moveCursor(-1); return true }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left) return adjustCursor(-1)
        if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            if (event.key === Qt.Key_L && mode === "stopwatch") { clockwork.lap(); return true }
            return adjustCursor(1)
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            moveCursor(event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? -1 : 1)
            return true
        }
        if (event.key === Qt.Key_Space) {
            if (mode === "alarm") addAlarm()
            else if (mode === "timer") addTimer(duration(), "")
            else startClockwork()
            return true
        }
        if (event.key === Qt.Key_R) {
            if (mode === "timer") setDuration(0)
            else if (mode === "alarm") resetAlarm()
            else resetClockwork()
            return true
        }
        if (event.key === Qt.Key_S && mode === "pomodoro") {
            clockwork.skipPomodoroPhase()
            return true
        }
        return defaultKey(event)
    }

    component Field: TextField {
        id: fieldInput
        readonly property bool navigable: enabled
        property bool cursored: false
        signal clicked(int button)
        onClicked: { forceActiveFocus(); selectAll() }
        height: Style.controlHeight; leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX; topPadding: 0; bottomPadding: 0
        color: root.shell.foreground; placeholderTextColor: root.shell.alpha(root.shell.foreground, .35)
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        onActiveFocusChanged: {
            root.wantsKeyboard = activeFocus
            if (activeFocus) root.selectRow(fieldInput)
        }
        onAccepted: { focus = false; Qt.callLater(() => root.resumeKeyboard()) }
        Keys.onEscapePressed: { focus = false; Qt.callLater(() => root.resumeKeyboard()) }
        Keys.onTabPressed: { focus = false; Qt.callLater(() => { root.resumeKeyboard(); root.moveCursor(1) }) }
        Keys.onBacktabPressed: { focus = false; Qt.callLater(() => { root.resumeKeyboard(); root.moveCursor(-1) }) }
        background: Rectangle {
            radius: root.shell.rounding
            color: fieldInput.cursored ? root.shell.hoverFill() : root.shell.alpha(root.shell.foreground, .06)
            border.width: fieldInput.cursored || fieldInput.activeFocus ? 2 : 1
            border.color: fieldInput.cursored ? root.shell.hoverEdge(.85)
                : root.shell.alpha(root.shell.foreground, fieldInput.activeFocus ? .45 : .18)
        }
    }
    component ModeTab: BarButton {
        property bool selected: false
        active: false; radius: shell.rounding; fill: "transparent"; outline: "transparent"; textColor: selected ? shell.accent : shell.alpha(shell.foreground, .6)
    }
    component PresetButton: BarButton { keyboardEnabled: true; radius: shell.rounding; fill: shell.alpha(shell.accent, .18); outline: "transparent"; textColor: shell.accent }
    property Component actionComponent: Component { Process {
        id: action; property string failure: ""
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: action.failure = String(text).trim() }
        onExited: (code, status) => { if (code !== 0) root.error = failure || "Could not update scheduled item"; root.changed(); destroy() }
    } }

    Column {
        id: timerColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        PopupHero {
            shell: root.shell; icon: "◷"; title: "Time Tools"; status: root.heroStatus()
            statusColor: Qt.darker(root.shell.foreground, 1.4)
        }
        PopupSeparator { shell: root.shell }
        Column {
            width: parent.width; spacing: Style.sm
            Row {
                width: parent.width; spacing: Style.sm
                Repeater {
                    model: root.primaryModes
                    ModeTab {
                        required property var modelData
                        width: (timerColumn.width - Style.sm * 2) / 3; height: Style.controlHeight
                        shell: root.shell; text: modelData.text; selected: root.mode === modelData.mode
                        enabled: !root.clockwork.running; opacity: enabled ? 1 : .35
                        onClicked: root.selectMode(modelData.mode)
                    }
                }
            }
            Row {
                width: parent.width; spacing: Style.sm
                Repeater {
                    model: root.secondaryModes
                    ModeTab {
                        required property var modelData
                        width: (timerColumn.width - Style.sm * 2) / 3; height: Style.controlHeight
                        shell: root.shell; text: modelData.text; selected: root.mode === modelData.mode
                        enabled: !root.clockwork.running; opacity: enabled ? 1 : .35
                        onClicked: root.selectMode(modelData.mode)
                    }
                }
            }
        }
        PopupSeparator { shell: root.shell }
        StackLayout {
            id: pages; width: parent.width
            currentIndex: root.mode === "timer" ? 0 : root.mode === "stopwatch" ? 1
                : root.mode === "countdown" ? 2 : root.mode === "alarm" ? 3
                : root.mode === "intervals" ? 4 : 5
            Column { spacing: Style.sectionGap
                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.lg
                    PopupNumberField {
                        width: Style.px(68); shell: root.shell; label: "H"; maximum: 99
                        value: root.timerHours; onCommitted: value => root.timerHours = value
                    }
                    Text {
                        height: Style.controlHeight + Style.title + Style.xs; text: ":"
                        color: root.shell.foreground; font.family: root.shell.fontFamily
                        font.pixelSize: Style.displayLarge; font.bold: true; verticalAlignment: Text.AlignBottom
                    }
                    PopupNumberField {
                        width: Style.px(68); shell: root.shell; label: "M"; maximum: 59
                        value: root.timerMinutes; onCommitted: value => root.timerMinutes = value
                    }
                    Text {
                        height: Style.controlHeight + Style.title + Style.xs; text: ":"
                        color: root.shell.foreground; font.family: root.shell.fontFamily
                        font.pixelSize: Style.displayLarge; font.bold: true; verticalAlignment: Text.AlignBottom
                    }
                    PopupNumberField {
                        width: Style.px(68); shell: root.shell; label: "S"; maximum: 59
                        value: root.timerSeconds; onCommitted: value => root.timerSeconds = value
                    }
                }
                Grid { width: parent.width; columns: 3; spacing: Style.sm
                    Repeater { model: [{text:"+1m", seconds:60}, {text:"+5m", seconds:300}, {text:"+10m", seconds:600}, {text:"+15m", seconds:900}, {text:"+30m", seconds:1800}, {text:"+1h", seconds:3600}]
                        PresetButton { required property var modelData; width: (pages.width - Style.sm * 2) / 3; height: Style.controlHeight; shell: root.shell; text: modelData.text; onClicked: root.addDuration(modelData.seconds) }
                    }
                }
                Text {
                    visible: root.duration() > 0; width: parent.width; height: Style.controlHeight
                    text: root.timerWhen().toUpperCase(); color: Qt.darker(root.shell.foreground, 1.4)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    font.bold: true; font.letterSpacing: 1.2
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                Field { id: timerLabel; width: parent.width; placeholderText: "Label (optional)" }
                Row { width: parent.width; spacing: Style.sm
                    BarButton { id: resetTimer; keyboardEnabled: true; width: (pages.width - Style.sm * 2) / 3; height: Style.controlHeight; shell: root.shell; radius: shell.rounding; fill: shell.alpha(shell.foreground, .06); outline: shell.alpha(shell.foreground, .18); text: "RESET"; onClicked: root.setDuration(0) }
                    BarButton { keyboardEnabled: true; width: parent.width - resetTimer.width - parent.spacing; height: Style.controlHeight; shell: root.shell; text: "START"; active: true; onClicked: root.addTimer(root.duration(), "") }
                }
            }
            ClockworkPage {
                shell: root.shell; clockwork: root.clockwork
                pageMode: root.clockwork.stopwatchMode
                onStartRequested: root.startClockwork()
                onResetRequested: root.resetClockwork()
            }
            ClockworkPage {
                shell: root.shell; clockwork: root.clockwork
                pageMode: root.clockwork.countdownMode
                onStartRequested: root.startClockwork()
                onResetRequested: root.resetClockwork()
            }
            Column {
                spacing: Style.sectionGap
                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.lg
                    PopupNumberField {
                        width: Style.px(68); shell: root.shell; label: "H"; maximum: 23
                        value: root.alarmHours
                        onCommitted: value => { root.alarmHours = value; root.error = "" }
                    }
                    Text {
                        height: Style.controlHeight + Style.title + Style.xs; text: ":"
                        color: root.shell.foreground; font.family: root.shell.fontFamily
                        font.pixelSize: Style.displayLarge; font.bold: true; verticalAlignment: Text.AlignBottom
                    }
                    PopupNumberField {
                        width: Style.px(68); shell: root.shell; label: "M"; maximum: 59
                        value: root.alarmMinutes
                        onCommitted: value => { root.alarmMinutes = value; root.error = "" }
                    }
                }
                Column { width: parent.width; spacing: Style.xs
                    PopupSection { shell: root.shell; text: "DAYS" }
                    Grid {
                        width: parent.width; columns: 4; spacing: Style.sm
                        Repeater {
                            model: root.alarmWeekdays
                            BarButton {
                                required property var modelData
                                width: (pages.width - Style.sm * 3) / 4; height: Style.controlHeight
                                shell: root.shell; text: modelData.text; tooltip: modelData.name
                                keyboardEnabled: true
                                active: root.alarmDaySelected(modelData.day)
                                radius: shell.rounding
                                fill: shell.alpha(shell.accent, active ? .32 : .18)
                                outline: "transparent"; textColor: shell.accent
                                onClicked: root.toggleAlarmDay(modelData.day)
                            }
                        }
                    }
                }
                Text {
                    width: parent.width; height: Style.controlHeight
                    text: root.alarmWhen().toUpperCase(); color: Qt.darker(root.shell.foreground, 1.4)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    font.bold: true; font.letterSpacing: 1.2
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                Field { id: alarmLabel; width: parent.width; placeholderText: "Label (optional)" }
                Row { width: parent.width; spacing: Style.sm
                    BarButton {
                        id: resetAlarmButton; width: (pages.width - Style.sm * 2) / 3
                        height: Style.controlHeight; shell: root.shell; text: "RESET"
                        keyboardEnabled: true
                        fill: shell.alpha(shell.foreground, .06); outline: shell.alpha(shell.foreground, .18)
                        onClicked: root.resetAlarm()
                    }
                    BarButton {
                        width: parent.width - resetAlarmButton.width - parent.spacing
                        height: Style.controlHeight; shell: root.shell
                        keyboardEnabled: true
                        text: root.alarmDays.length > 1 ? "ADD " + root.alarmDays.length + " ALARMS" : "ADD ALARM"
                        active: true; onClicked: root.addAlarm()
                    }
                }
            }
            ClockworkPage {
                shell: root.shell; clockwork: root.clockwork
                pageMode: root.clockwork.intervalsMode
                onStartRequested: root.startClockwork()
                onResetRequested: root.resetClockwork()
            }
            ClockworkPage {
                shell: root.shell; clockwork: root.clockwork
                pageMode: root.clockwork.pomodoroMode
                onStartRequested: root.startClockwork()
                onResetRequested: root.resetClockwork()
            }
        }
        Text {
            width: parent.width; text: root.hintText()
            color: Qt.darker(root.shell.foreground, 1.4); font.family: root.shell.fontFamily
            font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2
        }
        Text { visible: root.error !== ""; width: parent.width; text: root.error; color: root.shell.role("error", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "ACTIVE"; value: root.entries.length }
        Text { visible: root.entries.length === 0; width: parent.width; text: "No active alarms or timers"; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        ListView {
            visible: root.entries.length > 0; width: parent.width; height: Math.min(contentHeight, Style.px(180)); spacing: Style.sm; clip: true; model: root.entries
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: modelData.kind === "alarm" ? "󰀠" : "󰔛"; title: modelData.label || (modelData.kind === "alarm" ? "Alarm" : "Timer"); detail: (modelData.kind === "alarm" ? Qt.formatDateTime(new Date(modelData.epoch * 1000), "ddd HH:mm") : "Ends " + Qt.formatTime(new Date(modelData.epoch * 1000), "HH:mm")) + " · click to cancel"; value: root.remaining(modelData.epoch); active: true; onClicked: root.run(["cancel", String(modelData.id)]) }
        }
    }
}

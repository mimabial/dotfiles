pragma ComponentBehavior: Bound

import QtQuick

Column {
    id: root
    required property var shell
    required property var clockwork
    required property string pageMode
    signal startRequested
    signal resetRequested
    spacing: Style.sectionGap

    readonly property bool stopwatch: pageMode === clockwork.stopwatchMode
    readonly property bool countdown: pageMode === clockwork.countdownMode
    readonly property bool intervals: pageMode === clockwork.intervalsMode
    readonly property bool pomodoro: pageMode === clockwork.pomodoroMode
    readonly property bool canEditMajorTime: countdown && !clockwork.running
        && clockwork.storedElapsedMs === 0 && !clockwork.completed
    readonly property bool canEditPomodoro: pomodoro && !clockwork.pomodoroSessionStarted && !clockwork.completed
    readonly property bool threeActions: stopwatch
        || pomodoro && clockwork.pomodoroSessionStarted && !clockwork.completed

    Column {
        width: parent.width; spacing: Style.sm
        Row {
            visible: root.canEditMajorTime
            anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.lg
            PopupNumberField {
                shell: root.shell
                width: Style.px(68); label: "M"; maximum: 999
                value: root.clockwork.countdownMinutes
                onCommitted: value => root.clockwork.setCountdownMinutes(value)
            }
            Text {
                height: Style.controlHeight + Style.title + Style.xs; text: ":"
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.displayLarge; font.bold: true; verticalAlignment: Text.AlignBottom
            }
            PopupNumberField {
                shell: root.shell
                width: Style.px(68); label: "S"; maximum: 59
                value: root.clockwork.countdownSeconds
                onCommitted: value => root.clockwork.setCountdownSeconds(value)
            }
        }
        Text {
            visible: !root.canEditMajorTime
            width: parent.width; text: root.clockwork.displayText
            color: root.shell.foreground; font.family: root.shell.fontFamily
            font.pixelSize: Style.displayLarge; font.bold: true; horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width; text: root.clockwork.statusText.toUpperCase()
            color: Qt.darker(root.shell.foreground, 1.4); font.family: root.shell.fontFamily
            font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1.2
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Rectangle {
        visible: !root.stopwatch
        width: parent.width; height: Style.trackHeight; radius: height / 2
        color: root.shell.alpha(root.shell.foreground, .12)
        Rectangle {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: root.clockwork.progress <= 0 ? 0 : Math.max(height, parent.width * root.clockwork.progress)
            height: parent.height; radius: height / 2
            color: root.pomodoro && root.clockwork.pomodoroPhase.kind !== "focus"
                ? root.clockwork.pomodoroBreakColor : root.shell.accent
            Behavior on width { NumberAnimation { duration: 90 } }
        }
    }

    ListView {
        visible: root.stopwatch && root.clockwork.stopwatchLaps.length > 0
        width: parent.width; height: Math.min(contentHeight, Style.px(120)); spacing: Style.xs
        clip: true; model: root.clockwork.stopwatchLaps.slice().reverse()
        delegate: PopupRow {
            required property var modelData
            required property int index
            width: ListView.view.width; shell: root.shell
            title: "Lap " + (root.clockwork.stopwatchLaps.length - index)
            value: root.clockwork.formatTime(modelData, true)
        }
    }

    Column {
        visible: root.intervals; width: parent.width; spacing: Style.sm
        Text {
            width: parent.width; text: root.clockwork.intervalRounds + " × " + root.clockwork.intervalDurationText
            color: root.shell.alpha(root.shell.foreground, .7); font.family: root.shell.fontFamily
            font.pixelSize: Style.body; font.bold: true; horizontalAlignment: Text.AlignHCenter
        }
        Row {
            width: parent.width; spacing: Style.sm
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing * 2) / 3; label: "R"
                value: root.clockwork.intervalRounds; minimum: 1; enabled: !root.clockwork.running
                onCommitted: value => root.clockwork.setIntervalRounds(value)
            }
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing * 2) / 3; label: "M"
                value: root.clockwork.intervalMinutes; enabled: !root.clockwork.running
                onCommitted: value => root.clockwork.setIntervalMinutes(value)
            }
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing * 2) / 3; label: "S"
                value: root.clockwork.intervalSeconds; maximum: 59; enabled: !root.clockwork.running
                onCommitted: value => root.clockwork.setIntervalSeconds(value)
            }
        }
    }

    Column {
        visible: root.pomodoro; width: parent.width; spacing: Style.sm
        Text {
            width: parent.width
            text: root.clockwork.pomodoroSessionStarted
                ? root.clockwork.pomodoroCompletedCycles + " of " + root.clockwork.pomodoroCycles + " focus sessions complete"
                : root.clockwork.pomodoroWorkMinutes + " / " + root.clockwork.pomodoroShortBreakMinutes + " × "
                    + root.clockwork.pomodoroCycles + " · " + root.clockwork.pomodoroLongBreakMinutes + " long"
            color: root.shell.alpha(root.shell.foreground, .7); font.family: root.shell.fontFamily
            font.pixelSize: Style.body; font.bold: true; horizontalAlignment: Text.AlignHCenter
        }
        Grid {
            width: parent.width; columns: 2; spacing: Style.sm
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing) / 2; label: "Focus minutes"
                value: root.clockwork.pomodoroWorkMinutes; minimum: 1; enabled: root.canEditPomodoro
                onCommitted: value => root.clockwork.setPomodoroWorkMinutes(value)
            }
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing) / 2; label: "Short break"
                value: root.clockwork.pomodoroShortBreakMinutes; minimum: 1; enabled: root.canEditPomodoro
                onCommitted: value => root.clockwork.setPomodoroShortBreakMinutes(value)
            }
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing) / 2; label: "Cycles"
                value: root.clockwork.pomodoroCycles; minimum: 1; maximum: 99; enabled: root.canEditPomodoro
                onCommitted: value => root.clockwork.setPomodoroCycles(value)
            }
            PopupNumberField {
                shell: root.shell
                width: (parent.width - parent.spacing) / 2; label: "Long break"
                value: root.clockwork.pomodoroLongBreakMinutes; minimum: 1; enabled: root.canEditPomodoro
                onCommitted: value => root.clockwork.setPomodoroLongBreakMinutes(value)
            }
        }
        Row {
            width: parent.width; height: Style.controlHeight
            Text {
                width: parent.width - soundSwitch.width; anchors.verticalCenter: parent.verticalCenter
                text: "Pomodoro sounds"; color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            ToggleSwitch {
                id: soundSwitch; anchors.verticalCenter: parent.verticalCenter
                shell: root.shell; checked: root.clockwork.pomodoroSoundEnabled
                keyboardEnabled: root.canEditPomodoro
                enabled: root.canEditPomodoro; opacity: enabled ? 1 : .45
                onToggled: if (enabled) root.clockwork.setPomodoroSoundEnabled(!root.clockwork.pomodoroSoundEnabled)
            }
        }
    }

    Row {
        width: parent.width; spacing: Style.sm
        BarButton {
            width: root.threeActions
                ? (parent.width - parent.spacing * 2) / 3 : (parent.width - parent.spacing) / 2
            height: Style.controlHeight; shell: root.shell
            text: root.clockwork.running ? "PAUSE" : root.clockwork.completed ? "START AGAIN" : "START"
            active: root.clockwork.running
            enabled: root.stopwatch || root.clockwork.targetMs > 0
            opacity: enabled ? 1 : .4
            onClicked: root.startRequested()
        }
        BarButton {
            visible: root.stopwatch
            width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight
            shell: root.shell; text: "LAP"; enabled: root.clockwork.running
            radius: shell.rounding; fill: shell.alpha(shell.accent, .18)
            outline: "transparent"; textColor: shell.accent
            opacity: enabled ? 1 : .4; onClicked: root.clockwork.lap()
        }
        BarButton {
            visible: root.pomodoro && root.clockwork.pomodoroSessionStarted && !root.clockwork.completed
            width: (parent.width - parent.spacing * 2) / 3; height: Style.controlHeight
            shell: root.shell; text: "SKIP"; onClicked: root.clockwork.skipPomodoroPhase()
        }
        BarButton {
            width: root.threeActions
                ? (parent.width - parent.spacing * 2) / 3 : (parent.width - parent.spacing) / 2
            height: Style.controlHeight; shell: root.shell; text: "RESET"
            enabled: root.clockwork.active; opacity: enabled ? 1 : .4
            fill: root.shell.alpha(root.shell.foreground, .06); outline: root.shell.alpha(root.shell.foreground, .18)
            onClicked: root.resetRequested()
        }
    }
}

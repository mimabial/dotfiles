import QtQuick
import Quickshell

Item {
    id: root
    required property var shell

    readonly property string stopwatchMode: "stopwatch"
    readonly property string countdownMode: "countdown"
    readonly property string intervalsMode: "intervals"
    readonly property string pomodoroMode: "pomodoro"

    property string mode: stopwatchMode
    property bool running: false
    property bool completed: false
    property double startedAt: 0
    property double storedElapsedMs: 0
    property double nowMs: Date.now()
    property int notifiedIntervals: 0
    property int completionBellsRemaining: 0
    property var stopwatchLaps: []

    property int countdownMinutes: 5
    property int countdownSeconds: 0

    property int intervalRounds: 8
    property int intervalMinutes: 0
    property int intervalSeconds: 30

    property int pomodoroWorkMinutes: 25
    property int pomodoroShortBreakMinutes: 5
    property int pomodoroCycles: 4
    property int pomodoroLongBreakMinutes: 15
    property bool pomodoroSoundEnabled: true
    property color pomodoroBreakColor: "#a6e3a1"
    property string pomodoroPhaseKind: "focus"
    property int pomodoroCurrentCycle: 1
    property int pomodoroCompletedCycles: 0
    property bool pomodoroSessionStarted: false

    readonly property int intervalDurationMs: Math.max(1000, intervalMinutes * 60000 + intervalSeconds * 1000)
    readonly property string intervalDurationText: pad2(intervalMinutes) + ":" + pad2(intervalSeconds)
    readonly property double pomodoroWorkMs: Math.max(1, pomodoroWorkMinutes) * 60000
    readonly property double pomodoroShortBreakMs: Math.max(1, pomodoroShortBreakMinutes) * 60000
    readonly property double pomodoroLongBreakMs: Math.max(1, pomodoroLongBreakMinutes) * 60000
    readonly property double pomodoroPhaseDurationMs: pomodoroPhaseKind === "long-break"
        ? pomodoroLongBreakMs : pomodoroPhaseKind === "short-break" ? pomodoroShortBreakMs : pomodoroWorkMs
    readonly property double targetMs: mode === countdownMode
        ? Math.max(0, countdownMinutes * 60000 + countdownSeconds * 1000)
        : mode === intervalsMode ? Math.max(1, intervalRounds) * intervalDurationMs
        : mode === pomodoroMode ? pomodoroPhaseDurationMs : 0
    readonly property double elapsedMs: Math.max(0, Math.round(running ? storedElapsedMs + nowMs - startedAt : storedElapsedMs))
    readonly property var pomodoroPhase: ({
        kind: pomodoroPhaseKind,
        cycle: pomodoroCurrentCycle,
        label: pomodoroPhaseKind === "focus"
            ? "Focus " + pomodoroCurrentCycle + " of " + pomodoroCycles
            : pomodoroPhaseKind === "long-break" ? "Long break"
            : "Short break · Cycle " + pomodoroCurrentCycle + " of " + pomodoroCycles,
        durationMs: pomodoroPhaseDurationMs,
        elapsedMs: Math.min(elapsedMs, pomodoroPhaseDurationMs),
        remainingMs: Math.max(0, pomodoroPhaseDurationMs - elapsedMs)
    })
    readonly property double displayMs: mode === stopwatchMode ? elapsedMs
        : mode === pomodoroMode ? pomodoroPhase.remainingMs : Math.max(0, targetMs - elapsedMs)
    readonly property real progress: mode === stopwatchMode ? 0 : mode === pomodoroMode
        ? (pomodoroPhase.durationMs > 0 ? Math.min(1, pomodoroPhase.elapsedMs / pomodoroPhase.durationMs) : 0)
        : targetMs > 0 ? Math.min(1, elapsedMs / targetMs) : 0
    readonly property int currentRound: mode === intervalsMode
        ? Math.min(Math.max(1, intervalRounds), Math.floor(elapsedMs / intervalDurationMs) + 1) : 0
    readonly property bool active: running || storedElapsedMs > 0 || completed
        || (mode === pomodoroMode && pomodoroSessionStarted)
    readonly property string modeName: mode === stopwatchMode ? "Stopwatch"
        : mode === countdownMode ? "Countdown" : mode === intervalsMode ? "Intervals"
        : "Pomodoro"
    readonly property string statusText: {
        if (completed) return mode === intervalsMode ? "Workout complete"
            : mode === pomodoroMode ? "Pomodoro complete" : "Time is up"
        if (mode === pomodoroMode) {
            if (running) return pomodoroPhase.label
            if (pomodoroSessionStarted) return "Paused · " + pomodoroPhase.label
            return pomodoroCycles + " cycles · " + pomodoroWorkMinutes + " / " + pomodoroShortBreakMinutes + " min"
        }
        if (mode === intervalsMode) return "Round " + currentRound + " of " + intervalRounds + " · " + intervalDurationText
        if (running) return mode === stopwatchMode ? "Counting up" : "Counting down"
        if (storedElapsedMs > 0) return "Paused"
        return "Ready"
    }
    readonly property string displayText: formatTime(displayMs, mode === stopwatchMode)
    readonly property string barTimeText: active ? formatTime(displayMs, false) : ""

    function pad2(value) { return value < 10 ? "0" + value : String(value) }
    function formatTime(milliseconds, showCentiseconds) {
        const safeMilliseconds = Math.max(0, Math.floor(milliseconds))
        const total = showCentiseconds || mode === stopwatchMode
            ? Math.floor(safeMilliseconds / 1000) : Math.ceil(milliseconds / 1000)
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor(total % 3600 / 60)
        const seconds = total % 60
        const result = (hours > 0 ? hours + ":" + pad2(minutes) : pad2(minutes)) + ":" + pad2(seconds)
        if (!showCentiseconds) return result
        const centiseconds = Math.floor(safeMilliseconds % 1000 / 10)
        return result + "." + pad2(centiseconds)
    }
    function selectMode(nextMode) {
        if (nextMode === mode || ![stopwatchMode, countdownMode, intervalsMode, pomodoroMode].includes(nextMode)) return
        mode = nextMode
        reset()
    }
    function startPause() {
        if (running) {
            pause()
            return
        }
        if (completed) reset()
        if (mode !== stopwatchMode && targetMs <= 0) return
        if (mode === pomodoroMode) pomodoroSessionStarted = true
        nowMs = Date.now(); startedAt = nowMs; running = true
    }
    function pause() {
        if (!running) return
        nowMs = Date.now(); storedElapsedMs = elapsedMs; running = false
    }
    function reset() {
        running = false; completed = false; storedElapsedMs = 0; notifiedIntervals = 0
        nowMs = Date.now(); startedAt = nowMs
        if (mode === stopwatchMode) stopwatchLaps = []
        if (mode === pomodoroMode) {
            pomodoroPhaseKind = "focus"; pomodoroCurrentCycle = 1
            pomodoroCompletedCycles = 0; pomodoroSessionStarted = false
        }
    }

    function setCountdownMinutes(value) { countdownMinutes = Math.max(0, Math.min(999, Number(value) || 0)); reset() }
    function setCountdownSeconds(value) { countdownSeconds = Math.max(0, Math.min(59, Number(value) || 0)); reset() }
    function lap() {
        if (mode !== stopwatchMode || !running) return
        nowMs = Date.now()
        stopwatchLaps = stopwatchLaps.concat([elapsedMs])
    }
    function setIntervalRounds(value) { intervalRounds = Math.max(1, Math.min(999, Number(value) || 1)); reset() }
    function setIntervalMinutes(value) {
        intervalMinutes = Math.max(0, Math.min(999, Number(value) || 0))
        if (intervalMinutes === 0 && intervalSeconds === 0) intervalSeconds = 1
        reset()
    }
    function setIntervalSeconds(value) {
        intervalSeconds = Math.max(0, Math.min(59, Number(value) || 0))
        if (intervalMinutes === 0 && intervalSeconds === 0) intervalSeconds = 1
        reset()
    }
    function savePomodoro() {
        shell.store.clockworkWorkMinutes = pomodoroWorkMinutes
        shell.store.clockworkShortBreakMinutes = pomodoroShortBreakMinutes
        shell.store.clockworkCycles = pomodoroCycles
        shell.store.clockworkLongBreakMinutes = pomodoroLongBreakMinutes
        shell.store.clockworkSound = pomodoroSoundEnabled
        shell.store.clockworkBreakColor = String(pomodoroBreakColor)
    }
    function setPomodoroWorkMinutes(value) { pomodoroWorkMinutes = Math.max(1, Math.min(999, Number(value) || 1)); reset(); savePomodoro() }
    function setPomodoroShortBreakMinutes(value) { pomodoroShortBreakMinutes = Math.max(1, Math.min(999, Number(value) || 1)); reset(); savePomodoro() }
    function setPomodoroCycles(value) { pomodoroCycles = Math.max(1, Math.min(99, Number(value) || 1)); reset(); savePomodoro() }
    function setPomodoroLongBreakMinutes(value) { pomodoroLongBreakMinutes = Math.max(1, Math.min(999, Number(value) || 1)); reset(); savePomodoro() }
    function setPomodoroSoundEnabled(value) { pomodoroSoundEnabled = Boolean(value); savePomodoro() }

    function beginPomodoroPhase(kind, cycle, autoRun) {
        pomodoroPhaseKind = kind; pomodoroCurrentCycle = Math.max(1, Math.min(pomodoroCycles, Number(cycle)))
        storedElapsedMs = 0; nowMs = Date.now(); startedAt = nowMs
        running = Boolean(autoRun); completed = false; pomodoroSessionStarted = true
    }
    function skipPomodoroPhase() {
        if (mode !== pomodoroMode || !pomodoroSessionStarted || completed) return
        if (pomodoroPhaseKind === "focus") {
            beginPomodoroPhase("short-break", pomodoroCurrentCycle, true)
            notify("Focus skipped · Short break starts now")
        } else if (pomodoroPhaseKind === "short-break") {
            beginPomodoroPhase("focus", pomodoroCompletedCycles + 1, false)
            notify("Break skipped · Ready for focus " + pomodoroCurrentCycle)
        } else finishPomodoroCycle(false)
    }
    function completePomodoroPhase() {
        if (pomodoroPhaseKind === "focus") {
            pomodoroCompletedCycles = Math.min(pomodoroCycles, pomodoroCompletedCycles + 1)
            const longBreak = pomodoroCompletedCycles >= pomodoroCycles
            beginPomodoroPhase(longBreak ? "long-break" : "short-break", pomodoroCompletedCycles, true)
            playPomodoroSound()
            notify("Focus " + pomodoroCompletedCycles + " complete · " + (longBreak ? "Long" : "Short") + " break starts now")
        } else if (pomodoroPhaseKind === "long-break") finishPomodoroCycle(true)
        else {
            beginPomodoroPhase("focus", pomodoroCompletedCycles + 1, false)
            playPomodoroSound(); notify("Break complete · Ready for focus " + pomodoroCurrentCycle)
        }
    }
    function finishPomodoroCycle(withSound) {
        storedElapsedMs = pomodoroPhaseDurationMs; running = false; completed = true; pomodoroSessionStarted = true
        if (withSound) playCompletionSequence()
        notify("All " + pomodoroCycles + " focus cycles complete")
    }
    function tick() {
        nowMs = Date.now()
        if (!running || mode === stopwatchMode) return
        if (mode === intervalsMode) {
            const passed = Math.min(intervalRounds, Math.floor(elapsedMs / intervalDurationMs))
            if (passed > notifiedIntervals && passed < intervalRounds) {
                notifiedIntervals = passed; playSound("complete.oga")
                notify("Round " + passed + " complete · Round " + (passed + 1) + " starts now")
            }
        }
        if (mode === pomodoroMode && elapsedMs >= targetMs) { completePomodoroPhase(); return }
        if (elapsedMs >= targetMs) finish()
    }
    function finish() {
        if (!running) return
        storedElapsedMs = targetMs; running = false; completed = true
        notifiedIntervals = mode === intervalsMode ? intervalRounds : notifiedIntervals
        playCompletionSequence()
        notify(mode === intervalsMode ? "All " + intervalRounds + " rounds complete" : "Countdown complete")
    }
    function playSound(file) { Quickshell.execDetached(["pw-play", "--volume", "1.0", "/usr/share/sounds/freedesktop/stereo/" + file]) }
    function playPomodoroSound() { if (pomodoroSoundEnabled) playSound("complete.oga") }
    function playCompletionSequence() {
        if (mode === pomodoroMode && !pomodoroSoundEnabled) return
        completionBell.stop(); completionBellsRemaining = 3; playNextCompletionBell()
    }
    function playNextCompletionBell() {
        if (completionBellsRemaining <= 0) return
        playSound("complete.oga"); --completionBellsRemaining
        if (completionBellsRemaining > 0) completionBell.restart()
    }
    function notify(message) {
        Quickshell.execDetached(["dunstify", "-a", "Time Tools", "-h", "string:x-dunst-stack-tag:time-tools", "Time Tools", message])
    }

    Timer { interval: root.mode === root.stopwatchMode ? 10 : 100; repeat: true; running: root.running; onTriggered: root.tick() }
    Timer { id: completionBell; interval: 625; onTriggered: root.playNextCompletionBell() }
    Component.onCompleted: {
        pomodoroWorkMinutes = shell.store.clockworkWorkMinutes
        pomodoroShortBreakMinutes = shell.store.clockworkShortBreakMinutes
        pomodoroCycles = shell.store.clockworkCycles
        pomodoroLongBreakMinutes = shell.store.clockworkLongBreakMinutes
        pomodoroSoundEnabled = shell.store.clockworkSound
        pomodoroBreakColor = shell.store.clockworkBreakColor
    }
}

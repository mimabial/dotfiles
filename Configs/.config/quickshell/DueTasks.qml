import QtQuick
import Quickshell.Io
import "Units.js" as Units

Item {
    id: root
    required property var shell
    readonly property string helper: root.shell.home + "/.local/lib/hypr/calendar/agenda.sh"
    readonly property string execAt: root.shell.home + "/.local/lib/hypr/calendar/lib/exec_at.py"
    property int count: 0
    property var listDirs: []
    property var notified: ({})
    property bool primed: false
    property bool settingsLoaded: false
    property bool refreshQueued: false
    property double nextCheckMs: 0
    signal listsChanged()

    function refresh() { if (countProcess.running) refreshQueued = true; else countProcess.running = true }
    function dueMs(item) { return Number(item.due) * Units.MS_PER_SECOND }

    function announce(todos, now) {
        const seen = ({})
        for (const item of todos) {
            const id = String(item.id)
            seen[id] = true
            if (item.due === null || item.due === undefined) continue
            if (root.notified[id] === true) continue
            if (dueMs(item) > now) continue
            if (!root.settingsLoaded) continue
            root.notified[id] = true
            if (root.primed)
                root.shell.run(["notify-send", "-a", "Tasks", "-i", "task-due",
                    "Task due", String(item.summary || "")])
        }
        const kept = ({})
        for (const id in root.notified) if (seen[id] === true) kept[id] = true
        root.notified = kept
        store.setText(JSON.stringify({ notified: root.notified }))
        root.primed = true
    }

    function scheduleCheck(epochMs) {
        if (epochMs === nextCheckMs && dueWaiter.running) return
        nextCheckMs = epochMs
        dueWaiter.running = false
        dueWaiter.command = ["python3", execAt, String(epochMs / Units.MS_PER_SECOND), "true"]
        dueWaiter.running = true
    }

    Component.onCompleted: refresh()

    Process {
        id: countProcess
        command: ["bash", root.helper, "--todos"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            const todos = payload.todos || []
            const carried = Number(payload.carryNotice || 0)
            if (carried > 0)
                root.shell.run(["notify-send", "-a", "Tasks", "Tasks carried over",
                    carried + (carried === 1 ? " undated task is still open" : " undated tasks are still open")])
            const now = Date.now()
            const startOfTomorrow = new Date(new Date().getFullYear(), new Date().getMonth(),
                new Date().getDate() + 1).getTime()
            root.count = todos.filter(item => item.due !== null && item.due !== undefined
                && root.dueMs(item) < startOfTomorrow).length
            root.announce(todos, now)
            if (payload.listDirs) root.listDirs = payload.listDirs
            root.scheduleCheck(todos.reduce((soonest, item) => {
                const due = root.dueMs(item)
                return due > now && due < soonest ? due : soonest
            }, startOfTomorrow))
        } }
        onExited: if (root.refreshQueued) { root.refreshQueued = false; root.refresh() }
    }
    Process { id: dueWaiter; onExited: exitCode => { if (exitCode === 0) root.refresh() } }
    Process {
        id: listWatcher
        command: root.listDirs.length ? ["inotifywait", "--monitor", "--quiet", "--event", "close_write,create,delete,move"].concat(root.listDirs) : []
        running: listWatcher.command.length > 0
        stdout: SplitParser { onRead: { root.refresh(); root.listsChanged() } }
    }
    FileView {
        id: store
        path: root.shell.home + "/.local/state/quickshell/tasks.json"
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text()) || ({})
                root.notified = saved.notified || ({})
            } catch (error) { root.notified = ({}) }
            root.settingsLoaded = true
        }
        onLoadFailed: root.settingsLoaded = true
    }
}

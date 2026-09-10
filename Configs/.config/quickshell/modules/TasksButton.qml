pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool loaded: false
    property int dueCount: 0
    property bool notifyOnDue: true
    // ids already announced, so a task is not re-notified every scan
    property var notified: ({})

    css: "tasks"
    text: ""
    tooltip: ""
    active: root.shell.popupName === "tasks"
    // both states read from the style sheet: "tasks" for the idle colour and
    // "tasks.due" for the one with something due. Theme.box falls back to the
    // parent key, so a layout that names neither still resolves.
    readonly property var dueBox: root.shell.style.box("tasks.due")
    function specColor(spec, fallback) {
        if (!spec) return fallback
        return Array.isArray(spec)
            ? root.shell.alpha(root.shell.role(spec[0], root.shell.foreground), spec[1])
            : root.shell.role(spec, root.shell.foreground)
    }
    textColor: root.dueCount > 0
        ? root.specColor(root.dueBox.content, root.shell.role("c3", root.shell.foreground))
        : root.box.content !== undefined ? root.styleColor("content")
        : root.shell.foreground
    onClicked: { root.loaded = true; root.shell.togglePopup("tasks") }

    // hyprshell forks a shell per call, so the polling path runs the helper
    // directly
    readonly property string helper: root.shell.home + "/.local/lib/hypr/calendar/agenda.sh"

    Process {
        id: countProc
        command: ["bash", root.helper, "--todos"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            const todos = payload.todos || []
            const now = Date.now()
            const cutoff = new Date(new Date().getFullYear(), new Date().getMonth(),
                new Date().getDate() + 1).getTime()
            root.dueCount = todos.filter(item => item.due !== null && item.due !== undefined
                && Number(item.due) * 1000 < cutoff).length
            root.announce(todos, now)
        } }
    }

    // A task is announced once its due moment has passed. Undated tasks and
    // ones already past when first seen are recorded silently, so enabling
    // this does not dump a backlog of notifications.
    function announce(todos, now) {
        const seen = ({})
        for (const item of todos) {
            const id = String(item.id)
            seen[id] = true
            if (item.due === null || item.due === undefined) continue
            const due = Number(item.due) * 1000
            if (root.notified[id] === true) continue
            if (due > now) continue
            if (!root.settingsLoaded) continue
            root.notified[id] = true
            if (root.notifyOnDue && root.primed)
                root.shell.run(["notify-send", "-a", "Tasks", "-i", "task-due",
                    "Task due", String(item.summary || "")])
        }
        // forget ids that no longer exist so the file cannot grow forever
        const kept = ({})
        for (const id in root.notified) if (seen[id] === true) kept[id] = true
        root.notified = kept
        root.store.setText(JSON.stringify({ notified: root.notified }))
        root.primed = true
    }
    // the first scan of a session only records; it never notifies
    property bool primed: false
    property bool settingsLoaded: false

    property FileView store: FileView {
        path: root.shell.home + "/.local/state/quickshell/tasks.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text()) || ({})
                root.notified = saved.notified || ({})
            } catch (error) { root.notified = ({}) }
            root.settingsLoaded = true
        }
        onLoadFailed: root.settingsLoaded = true
    }

    function refresh() { if (!countProc.running) countProc.running = true }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.popupsAllowed && root.shell.popupName === "tasks") root.loaded = true
            else if (root.shell.popupName === "") root.refresh()
        }
    }
    Loader {
        active: root.loaded; visible: false
        sourceComponent: Component {
            TasksPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
        }
    }
}

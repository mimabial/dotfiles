pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "tasks"
    contentWidth: Style.px(420)
    contentHeight: Math.max(tasksColumn.implicitHeight,
        showHelp ? helpColumn.implicitHeight : 0) + padding * 2
    wantsKeyboard: true

    property var todos: []
    property bool unavailable: false
    property string view: "today"
    property int cursor: 0
    property string pendingDelete: ""
    property Item confirmingRow: null
    property Item editingRow: null
    property bool showHelp: false
    property string editingId: ""
    property var taskOrder: []
    onShowHelpChanged: if (open) leaveAdd()

    function leaveAdd() {
        addField.focus = false
        taskKeys.forceActiveFocus()
    }

    readonly property var views: ["today", "overdue", "all", "done"]
    property string categoryFilter: ""
    readonly property var allCategories: {
        const seen = ({})
        const out = []
        for (const item of todos)
            for (const tag of (item.categories || [])) {
                const name = String(tag)
                if (name !== "" && seen[name] !== true) { seen[name] = true; out.push(name) }
            }
        out.sort()
        return out
    }
    readonly property string activeFilter:
        allCategories.indexOf(categoryFilter) >= 0 ? categoryFilter : ""
    function matchesFilter(item) {
        if (activeFilter === "") return true
        return (item.categories || []).some(tag => String(tag) === activeFilter)
    }

    function taskKey(item) { return String(item.uid || (item.list + ":" + item.id)) }
    function ordered(items) {
        const rank = ({})
        for (let index = 0; index < taskOrder.length; index++) rank[String(taskOrder[index])] = index
        return items.slice().sort((left, right) => {
            const a = rank[taskKey(left)], b = rank[taskKey(right)]
            return a === undefined ? (b === undefined ? 0 : 1) : (b === undefined ? -1 : a - b)
        })
    }
    readonly property var orderedTodos: ordered(todos)

    function startOfToday() {
        const now = new Date()
        return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    }
    function dueMillis(item) {
        return (item.due === null || item.due === undefined) ? -1 : Number(item.due) * 1000
    }
    function isOverdue(item) {
        const due = dueMillis(item)
        return due >= 0 && due < startOfToday()
    }
    function isToday(item) {
        const due = dueMillis(item)
        return due >= startOfToday() && due < startOfToday() + 86400000
    }
    readonly property var open_: orderedTodos.filter(item => item.completed !== true)
    readonly property var listed: {
        const base = view === "done" ? orderedTodos.filter(item => item.completed === true)
            : view === "all" ? open_
            : view === "overdue" ? open_.filter(item => isOverdue(item))
            : open_.filter(item => isOverdue(item) || isToday(item) || dueMillis(item) < 0)
        return base.filter(item => matchesFilter(item))
    }
    readonly property var sections: {
        const rows = listed
        const out = []
        let offset = 0
        const push = function (label, items) {
            if (items.length === 0) return
            out.push({ label: label, items: items, offset: offset })
            offset += items.length
        }
        if (view === "done") { push("COMPLETED", rows); return out }
        if (view === "overdue") { push("OVERDUE", rows); return out }
        push("OVERDUE", rows.filter(item => isOverdue(item)))
        push("TODAY", rows.filter(item => isToday(item)))
        if (view === "all")
            push("LATER", rows.filter(item => !isOverdue(item) && !isToday(item)
                && dueMillis(item) >= 0))
        push("CARRIED", rows.filter(item => dueMillis(item) < 0 && Number(item.carries || 0) > 0))
        push("NO DATE", rows.filter(item => dueMillis(item) < 0 && Number(item.carries || 0) === 0))
        return out
    }
    readonly property int dueCount: open_.filter(item => isOverdue(item) || isToday(item)).length

    function priorityIndex(item) {
        const priority = Number(item.priority || 0)
        return priority >= 1 && priority <= 4 ? 3 : priority === 5 ? 2 : priority >= 6 ? 1 : 0
    }
    function priorityName(item) { return ["none", "low", "medium", "high"][priorityIndex(item)] }
    function shiftPriority(item, delta) {
        const next = Math.max(0, Math.min(3, priorityIndex(item) + delta))
        if (next !== priorityIndex(item))
            run(["--todo-edit", String(item.id), "--priority", ["none", "low", "medium", "high"][next]])
    }

    // iCalendar runs 1 (highest) to 9; 5 is the middle and 0 means unset
    function priorityColor(item) {
        const priority = Number(item.priority || 0)
        if (priority >= 1 && priority <= 4) return shell.role("error", shell.foreground)
        if (priority === 5) return shell.role("warning", shell.foreground)
        if (priority >= 6) return shell.role("info", shell.foreground)
        return shell.alpha(shell.foreground, .45)
    }
    // todoman writes a date-only DUE as local midnight and a timed one at its
    // actual time, so midnight is what separates the two.
    function hasTime(item) {
        const due = dueMillis(item)
        if (due < 0) return false
        const date = new Date(due)
        return date.getHours() !== 0 || date.getMinutes() !== 0
    }
    function dueLabel(item) {
        const due = dueMillis(item)
        if (due < 0) return ""
        const date = new Date(due)
        const time = hasTime(item) ? "  " + Qt.formatDateTime(date, "HH:mm") : ""
        if (isToday(item)) return "today" + time
        const day = Qt.formatDate(date,
            date.getFullYear() === new Date().getFullYear() ? "d MMM" : "d MMM yyyy")
        return day + time
    }
    function taskMeta(item) {
        const parts = []
        const priority = priorityName(item)
        if (priority !== "none") parts.push(priority)
        if (item.completed === true) {
            const completed = completedLabel(item)
            if (completed !== "") parts.push(completed)
            const due = dueLabel(item)
            if (due !== "") parts.push("due " + due)
        } else {
            const due = dueLabel(item)
            if (due !== "") parts.push(due)
        }
        if (Number(item.carries || 0) > 0) parts.push("↻" + item.carries + " carried")
        return parts.join("  ·  ")
    }

    readonly property date now: shell.clock.date
    function dayKey(date) { return Qt.formatDate(date, "yyyy-MM-dd") }
    readonly property string todayKey: dayKey(now)
    readonly property var stats: {
        const start = startOfToday(), end = start + 86400000
        let done = 0, total = 0
        for (const item of orderedTodos) {
            const due = dueMillis(item)
            const completed = Number(item.completed_at || 0) * 1000
            if ((!item.completed && (due < 0 || due < end))
                    || (due >= start && due < end)
                    || (completed >= start && completed < end)) {
                total++
                if (item.completed) done++
            }
        }
        return { done: done, total: total, ratio: total > 0 ? done / total : 0 }
    }
    readonly property real dayFraction: {
        const hour = now.getHours() + now.getMinutes() / 60
        return Math.max(0, Math.min(1, (hour - 8) / 14))
    }
    readonly property var mood: {
        const moods = {
            idle: { label: "Idle", tagline: "Give the day a shape.", smile: .2, eyes: "flat", brow: 0, sweat: 0, sparkle: 0, wavy: false, urgency: 0 },
            done: { label: "Relaxed", tagline: "Done and dusted.", smile: 1, eyes: "happy", brow: 0, sweat: 0, sparkle: 2, wavy: false, urgency: 0 },
            easy: { label: "Easy", tagline: "Comfortably ahead.", smile: .8, eyes: "happy", brow: 0, sweat: 0, sparkle: 0, wavy: false, urgency: .1 },
            focused: { label: "Focused", tagline: "Steady as it goes.", smile: .3, eyes: "open", brow: .2, sweat: 0, sparkle: 0, wavy: false, urgency: .3 },
            worried: { label: "Worried", tagline: "The day is getting on.", smile: -.4, eyes: "open", brow: .65, sweat: 1, sparkle: 0, wavy: false, urgency: .62 },
            stressed: { label: "Stressed", tagline: "Pick one and start it.", smile: -.9, eyes: "wide", brow: 1, sweat: 2, sparkle: 0, wavy: true, urgency: 1 }
        }
        if (stats.total === 0) return moods.idle
        if (stats.done === stats.total) return moods.done
        const gap = dayFraction - stats.ratio
        return gap < .15 ? moods.easy : gap < .35 ? moods.focused : gap < .6 ? moods.worried : moods.stressed
    }
    readonly property var completionsByDay: {
        const counts = ({})
        for (const item of todos) if (Number(item.completed_at || 0) > 0) {
            const key = dayKey(new Date(Number(item.completed_at) * 1000))
            counts[key] = (counts[key] || 0) + 1
        }
        return counts
    }
    readonly property var history: {
        const days = [], date = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        for (let offset = 13; offset >= 0; offset--) {
            const day = new Date(date); day.setDate(day.getDate() - offset)
            days.push({ key: dayKey(day), count: completionsByDay[dayKey(day)] || 0 })
        }
        return days
    }
    readonly property int historyMax: Math.max(1, ...history.map(day => day.count))
    readonly property int streak: {
        const day = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        if (!completionsByDay[dayKey(day)]) day.setDate(day.getDate() - 1)
        let count = 0
        while (completionsByDay[dayKey(day)]) { count++; day.setDate(day.getDate() - 1) }
        return count
    }
    readonly property int completedRetained: todos.filter(item => item.completed === true).length

    readonly property var weekdayNames: ["sunday", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday"]
    readonly property var monthNames: ["jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"]

    function dateOnly(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate())
    }
    function nextWeekday(index) {
        const now = dateOnly(new Date())
        const ahead = (index - now.getDay() + 7) % 7
        now.setDate(now.getDate() + (ahead === 0 ? 7 : ahead))
        return now
    }
    // Recognises a date phrase and a priority token anywhere in the text and
    // hands back the words that are left as the summary.
    function parseQuickAdd(raw) {
        let words = String(raw).trim().split(/\s+/).filter(word => word !== "")
        let due = null
        let priority = ""
        let time = ""
        const tags = []
        const kept = []

        for (let at = 0; at < words.length; at++) {
            const word = words[at].toLowerCase()
            const next = at + 1 < words.length ? words[at + 1].toLowerCase() : ""

            if (priority === "") {
                const bang = word.match(/^!(high|medium|low|h|m|l)$/)
                if (bang) {
                    priority = bang[1][0] === "h" ? "high" : bang[1][0] === "m" ? "medium" : "low"
                    continue
                }
                const pn = word.match(/^p([1-4])$/)
                if (pn) {
                    priority = pn[1] === "1" ? "high" : pn[1] === "2" ? "medium"
                        : pn[1] === "3" ? "low" : "none"
                    continue
                }
            }
            if (word.charAt(0) === "+" && word.length > 1) {
                tags.push(words[at].slice(1))
                continue
            }
            const clock = (word === "at" ? next : word)
                .match(/^(\d{1,2})(?::(\d{2}))?(am|pm)?$/)
            if (time === "" && clock && (clock[2] !== undefined || clock[3] !== undefined)) {
                let hour = Number(clock[1])
                const minute = clock[2] === undefined ? 0 : Number(clock[2])
                if (clock[3] === "pm" && hour < 12) hour += 12
                if (clock[3] === "am" && hour === 12) hour = 0
                if (hour < 24 && minute < 60) {
                    time = ("0" + hour).slice(-2) + ":" + ("0" + minute).slice(-2)
                    if (word === "at") at++
                    continue
                }
            }

            if (due !== null) { kept.push(words[at]); continue }

            if (word === "today" || word === "tod") { due = dateOnly(new Date()); continue }
            if (word === "tomorrow" || word === "tmr" || word === "tom") {
                due = dateOnly(new Date()); due.setDate(due.getDate() + 1); continue
            }
            if (/^\d{4}-\d{2}-\d{2}$/.test(word)) {
                const parsed = new Date(word + "T12:00:00")
                if (!isNaN(parsed.getTime())) { due = dateOnly(parsed); continue }
            }
            const named = weekdayNames.findIndex(name => name === word || name.slice(0, 3) === word)
            if (named >= 0) { due = nextWeekday(named); continue }
            if (word === "next") {
                const after = weekdayNames.findIndex(name => name === next || name.slice(0, 3) === next)
                if (after >= 0) { due = nextWeekday(after); at++; continue }
                if (next === "week") {
                    due = dateOnly(new Date()); due.setDate(due.getDate() + 7); at++; continue
                }
            }
            if (word === "in" && /^\d+$/.test(next) && at + 2 < words.length) {
                const unit = words[at + 2].toLowerCase()
                const count = Number(next)
                if (/^days?$/.test(unit) || /^weeks?$/.test(unit)) {
                    due = dateOnly(new Date())
                    due.setDate(due.getDate() + count * (/^weeks?$/.test(unit) ? 7 : 1))
                    at += 2
                    continue
                }
            }
            // "25 sep" and "sep 25", this year unless that is already past
            const dayFirst = word.match(/^(\d{1,2})$/)
            const monthIndex = monthNames.indexOf(next.slice(0, 3))
            if (dayFirst && monthIndex >= 0) {
                due = dateOnly(new Date(new Date().getFullYear(), monthIndex, Number(dayFirst[1])))
                if (due < dateOnly(new Date())) due.setFullYear(due.getFullYear() + 1)
                at++
                continue
            }
            const monthFirst = monthNames.indexOf(word.slice(0, 3))
            if (monthFirst >= 0 && /^\d{1,2}$/.test(next)) {
                due = dateOnly(new Date(new Date().getFullYear(), monthFirst, Number(next)))
                if (due < dateOnly(new Date())) due.setFullYear(due.getFullYear() + 1)
                at++
                continue
            }
            kept.push(words[at])
        }
        return {
            summary: kept.join(" "),
            due: due === null ? "" : Qt.formatDate(due, "yyyy-MM-dd"),
            time: time,
            tags: tags,
            priority: priority
        }
    }
    function quickAddPreview(raw) {
        const parsed = parseQuickAdd(raw)
        if (parsed.summary === "") return ""
        const parts = [parsed.summary]
        if (parsed.due !== "")
            parts.push(Qt.formatDate(dateFromIsoDay(parsed.due), "ddd d MMM")
                + (parsed.time === "" ? "" : " " + parsed.time))
        for (const tag of parsed.tags) parts.push("+" + tag)
        if (parsed.priority !== "") parts.push(parsed.priority)
        return parts.join("  ·  ")
    }
    function dateFromIsoDay(iso) { return new Date(String(iso) + "T12:00:00") }

    function refresh() {
        readProc.running = false
        readProc.command = ["hyprshell", "calendar/agenda", "--todos-all"]
        readProc.running = true
    }
    // every mutation re-reads the whole set, completed included, or a task
    // that was just ticked off would vanish instead of moving to DONE
    function run(args) {
        pendingDelete = ""
        editingId = ""
        readProc.running = false
        readProc.command = ["hyprshell", "calendar/agenda"].concat(args).concat(["--todos-all"])
        readProc.running = true
    }
    function complete(item) { run(["--todo-done", String(item.id)]) }
    function reopen(item) { run(["--todo-open", String(item.id)]) }
    function toggle(item) {
        if (item.completed === true) reopen(item)
        else complete(item)
    }
    function completedLabel(item) {
        if (item.completed_at === null || item.completed_at === undefined) return ""
        const when = new Date(Number(item.completed_at) * 1000)
        const days = Math.round((startOfToday() - new Date(when.getFullYear(),
            when.getMonth(), when.getDate()).getTime()) / 86400000)
        if (days <= 0) return "done today"
        if (days === 1) return "done yesterday"
        if (days < 7) return "done " + days + " days ago"
        return "done " + Qt.formatDate(when, "d MMM")
    }
    function remove(item) {
        if (pendingDelete !== String(item.id)) {
            pendingDelete = String(item.id)
            return
        }
        run(["--todo-delete", String(item.id)])
    }
    function beginEdit(item) {
        pendingDelete = ""
        leaveAdd()
        editingId = taskKey(item)
    }
    function finishEdit(item, value, commit) {
        if (editingId !== taskKey(item)) return
        editingId = ""
        const summary = String(value).trim()
        if (commit && summary !== "" && summary !== String(item.summary))
            run(["--todo-edit", String(item.id), "--title", summary])
    }
    function move(delta) {
        if (listed.length === 0) return
        cursor = Math.max(0, Math.min(listed.length - 1, cursor + delta))
        pendingDelete = ""
    }
    function cycleView(delta) {
        const at = views.indexOf(view)
        view = views[(at + delta + views.length) % views.length]
    }
    function sectionPosition(item) {
        const key = taskKey(item)
        for (const section of sections)
            for (let index = 0; index < section.items.length; index++)
                if (taskKey(section.items[index]) === key) return { section: section, index: index }
        return null
    }
    function canReorder(item, delta) {
        const position = sectionPosition(item)
        return position && position.index + delta >= 0
            && position.index + delta < position.section.items.length
    }
    function reorder(item, delta) {
        const position = sectionPosition(item)
        if (!position || !canReorder(item, delta)) return
        const target = position.section.items[position.index + delta]
        const keys = orderedTodos.map(todo => taskKey(todo))
        const from = keys.indexOf(taskKey(item)), to = keys.indexOf(taskKey(target))
        const swap = keys[from]; keys[from] = keys[to]; keys[to] = swap
        taskOrder = keys
        orderFile.setText(JSON.stringify(keys) + "\n")
        cursor = position.section.offset + position.index + delta
        pendingDelete = ""
    }
    function handleKey(event) {
        if (addField.activeFocus || editingId !== "") return false
        const item = listed[cursor]
        switch (event.key) {
        case Qt.Key_Down: move(1); break
        case Qt.Key_Up: move(-1); break
        case Qt.Key_J:
            if (event.modifiers & Qt.ShiftModifier) { if (item) reorder(item, 1) }
            else move(1)
            break
        case Qt.Key_K:
            if (event.modifiers & Qt.ShiftModifier) { if (item) reorder(item, -1) }
            else move(-1)
            break
        case Qt.Key_Tab: cycleView(1); break
        case Qt.Key_Backtab: cycleView(-1); break
        case Qt.Key_T: view = "today"; break
        case Qt.Key_O: view = "overdue"; break
        case Qt.Key_A: view = "all"; break
        case Qt.Key_D: view = "done"; break
        case Qt.Key_R: refresh(); break
        case Qt.Key_Question: showHelp = !showHelp; break
        case Qt.Key_Q: addField.forceActiveFocus(); break
        case Qt.Key_E: if (item) beginEdit(item); break
        case Qt.Key_Left: case Qt.Key_H: if (item) shiftPriority(item, 1); break
        case Qt.Key_Right: case Qt.Key_L: if (item) shiftPriority(item, -1); break
        case Qt.Key_Space: case Qt.Key_Return: case Qt.Key_Enter: if (item) toggle(item); break
        case Qt.Key_X: if (item) remove(item); break
        case Qt.Key_Escape:
            if (showHelp) { showHelp = false; break }
            if (pendingDelete !== "") { pendingDelete = ""; break }
            return defaultKey(event)
        default: return false
        }
        return true
    }

    onViewChanged: { cursor = 0; pendingDelete = "" }
    onCategoryFilterChanged: { cursor = 0; pendingDelete = "" }
    onOpenChanged: {
        if (!open) {
            addField.focus = false
            pendingDelete = ""
            editingId = ""
            showHelp = false
            return
        }
        view = "today"
        cursor = 0
        categoryFilter = ""
        refresh()
        leaveAdd()
    }

    property Process readProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            root.todos = payload.todos || []
            root.unavailable = payload.unavailable === true
            if (root.cursor >= root.listed.length) root.cursor = Math.max(0, root.listed.length - 1)
        } }
    }
    property FileView orderFile: FileView {
        path: root.shell.home + "/.local/state/quickshell/task-order.json"
        watchChanges: true; printErrors: false; atomicWrites: true
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.taskOrder = Array.isArray(saved) ? saved.map(value => String(value)) : []
            } catch (error) { root.taskOrder = [] }
        }
        onFileChanged: reload()
    }
    property Timer poll: Timer {
        interval: 120000; running: root.open; repeat: true
        onTriggered: root.refresh()
    }

    component HelpRow: Item {
        required property string keys
        required property string action
        width: parent ? parent.width : 0
        height: Style.px(18)
        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: Style.px(110)
            text: parent.keys
            color: root.shell.role("act_br", root.shell.accent)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: Style.px(110)
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: parent.action; elide: Text.ElideRight
            color: root.shell.alpha(root.shell.foreground, .7)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    component TaskAction: Text {
        id: action
        required property string glyph
        property string hint: ""
        property color tone: root.shell.foreground
        signal triggered(int button)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.px(18)
        text: glyph; horizontalAlignment: Text.AlignHCenter
        color: root.shell.alpha(tone, actionArea.containsMouse ? 1 : .58)
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        MouseArea {
            id: actionArea
            anchors.fill: parent; anchors.margins: -Style.xs
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: mouse => action.triggered(mouse.button)
        }
        BarTooltip { shell: root.shell; anchorItem: action; text: action.hint; hovered: actionArea.containsMouse }
    }

    component ViewTab: Rectangle {
        required property string name
        readonly property bool current: root.view === name
        implicitWidth: tabLabel.implicitWidth + Style.controlPaddingX * 4
        implicitHeight: Style.px(28)
        radius: root.shell.rounding
        color: current ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .35)
            : tabArea.containsMouse ? root.shell.alpha(root.shell.foreground, .1) : "transparent"
        border.width: 1
        border.color: root.shell.alpha(root.shell.foreground, current ? .4 : .16)
        Text {
            id: tabLabel
            anchors.centerIn: parent
            text: parent.name.toUpperCase()
            color: root.shell.alpha(root.shell.foreground, parent.current ? 1 : .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            font.letterSpacing: 1
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.view = parent.name
        }
    }

    FocusScope {
        id: taskKeys
        anchors.fill: parent
        focus: true

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: eventPoint => {
                if (root.editingRow) {
                    const editPoint = root.editingRow.mapFromItem(taskKeys,
                        eventPoint.position.x, eventPoint.position.y)
                    if (editPoint.x < 0 || editPoint.y < 0
                            || editPoint.x > root.editingRow.width
                            || editPoint.y > root.editingRow.height)
                        root.editingRow.finish(true)
                }
                if (addField.activeFocus) {
                    const fieldPoint = addField.mapFromItem(taskKeys,
                        eventPoint.position.x, eventPoint.position.y)
                    if (fieldPoint.x < 0 || fieldPoint.y < 0
                            || fieldPoint.x > addField.width
                            || fieldPoint.y > addField.height)
                        root.leaveAdd()
                }
                if (root.pendingDelete === "" || !root.confirmingRow) return
                const point = root.confirmingRow.mapFromItem(taskKeys,
                    eventPoint.position.x, eventPoint.position.y)
                if (point.x < 0 || point.y < 0
                        || point.x > root.confirmingRow.width
                        || point.y > root.confirmingRow.height)
                    root.pendingDelete = ""
            }
        }

        Keys.onPressed: event => event.accepted = root.handleKey(event)

        Column {
            id: tasksColumn
            anchors.left: parent.left; anchors.right: parent.right
            spacing: Style.sm
            opacity: root.showHelp ? 0 : 1
            visible: opacity > 0

            Item {
                id: hero
                width: parent.width
                height: Style.px(54)
                TasksMascot {
                    id: heroMascot
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -Style.xxs
                    width: parent.height; height: width
                    cornerRadius: root.shell.rounding
                    baseColor: root.shell.foreground
                    alertColor: root.shell.role("error", root.shell.foreground)
                    urgency: root.mood.urgency; smile: root.mood.smile; eyes: root.mood.eyes
                    brow: root.mood.brow; sweat: root.mood.sweat
                    sparkle: root.mood.sparkle; wavy: root.mood.wavy
                    animated: root.open
                }
                Text {
                    id: heroCount
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stats.total > 0 ? root.stats.done + "/" + root.stats.total : "–"
                    color: root.shell.alpha(root.shell.foreground, .5)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.heroIcon; font.bold: true
                }
                Column {
                    anchors.left: heroMascot.right; anchors.leftMargin: Style.xxxl
                    anchors.right: heroCount.left; anchors.rightMargin: Style.xl
                    anchors.verticalCenter: parent.verticalCenter; spacing: Style.xxs
                    Text {
                        width: parent.width; text: Qt.formatDate(root.now, "dddd d MMMM"); elide: Text.ElideRight
                        color: root.shell.foreground; font.family: root.shell.fontFamily
                        font.pixelSize: Style.title; font.bold: true
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root.unavailable ? "TODOMAN IS NOT INSTALLED" : root.mood.label.toUpperCase()
                        color: heroMascot.inkColor; font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1.2
                    }
                    Text {
                        width: parent.width; text: root.mood.tagline; elide: Text.ElideRight
                        color: root.shell.alpha(root.shell.foreground, .5)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }

            Column {
                width: parent.width; spacing: Style.xs
                Item {
                    width: parent.width; height: Style.px(9)
                    Rectangle { id: progressTrack; anchors.fill: parent; radius: Math.min(height / 2, root.shell.rounding); color: root.shell.alpha(root.shell.foreground, .12) }
                    Rectangle {
                        anchors.left: parent.left; height: parent.height; radius: Math.min(height / 2, root.shell.rounding)
                        width: Math.max(root.stats.done > 0 ? height : 0, parent.width * root.stats.ratio)
                        color: heroMascot.inkColor
                        Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        visible: root.stats.total > 0 && root.stats.done < root.stats.total
                        width: Math.max(1, Style.xxs); height: parent.height + Style.sm
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(parent.width - width, Math.round(parent.width * root.dayFraction))
                        color: root.shell.foreground; opacity: .85
                    }
                }
                Item {
                    width: parent.width; height: progressDone.implicitHeight
                    Text {
                        id: progressDone; anchors.left: parent.left
                        text: root.stats.total > 0 ? Math.round(root.stats.ratio * 100) + "% of today done" : "Nothing planned yet"
                        color: root.shell.alpha(root.shell.foreground, .42)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                    Text {
                        anchors.right: parent.right
                        text: Math.round(root.dayFraction * 100) + "% of the workday gone"
                        color: root.shell.alpha(root.shell.foreground, .42)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }

            Item { width: 1; height: Style.xs }

            Item {
                width: parent.width
                height: addField.height
                visible: !root.unavailable
                PopupField {
                    id: addField
                    shell: root.shell
                    height: Style.px(32)
                    anchors.left: parent.left
                    anchors.right: parent.right
                    rightPadding: Style.controlPaddingX + Style.px(20) + Style.sm
                    placeholderText: "Add a task… (friday 5pm, +work, p1)"
                    function submit() {
                        const parsed = root.parseQuickAdd(addField.text)
                        if (parsed.summary === "") return
                        const args = ["--todo-add", "--title", parsed.summary]
                        if (parsed.due !== "") args.push("--day", parsed.due)
                        if (parsed.time !== "") args.push("--time", parsed.time)
                        for (const tag of parsed.tags) args.push("--category", tag)
                        if (parsed.priority !== "") args.push("--priority", parsed.priority)
                        root.run(args)
                        addField.text = ""
                    }
                    onSubmitted: addField.submit()
                    Keys.onReturnPressed: addField.submit()
                    Keys.onEnterPressed: addField.submit()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) root.leaveAdd()
                        else if (event.key === Qt.Key_Tab) root.cycleView(1)
                        else if (event.key === Qt.Key_Backtab) root.cycleView(-1)
                        else if (event.key === Qt.Key_Question || event.text === "?")
                            root.showHelp = true
                        else return
                        event.accepted = true
                    }
                }
                Text {
                    id: addButton
                    anchors.right: parent.right
                    anchors.rightMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.px(20)
                    horizontalAlignment: Text.AlignHCenter
                    text: "\u{f0415}"
                    color: addField.text !== ""
                        ? root.shell.role("act_br", root.shell.accent)
                        : root.shell.alpha(root.shell.foreground, addArea.containsMouse ? .9 : .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    MouseArea {
                        id: addArea
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: addField.submit()
                    }
                }
            }

            Text {
                width: parent.width
                visible: text !== "" && addField.activeFocus
                text: root.quickAddPreview(addField.text)
                elide: Text.ElideRight
                color: root.shell.role("act_br", root.shell.accent)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }

            Item { width: 1; height: Style.xs }

            Row {
                spacing: Style.sm
                Repeater {
                    model: root.views
                    ViewTab {
                        required property var modelData
                        name: String(modelData)
                    }
                }
            }

            Row {
                spacing: Style.sm
                visible: root.allCategories.length > 0
                Repeater {
                    model: [""].concat(root.allCategories)
                    Text {
                        required property var modelData
                        readonly property bool current: root.activeFilter === String(modelData)
                        text: String(modelData) === "" ? "all" : "+" + modelData
                        color: current ? root.shell.role("act_br", root.shell.accent)
                            : root.shell.alpha(root.shell.foreground, tagArea.containsMouse ? .8 : .4)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        MouseArea {
                            id: tagArea
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.categoryFilter = String(parent.modelData)
                        }
                    }
                }
            }

            PopupSeparator { shell: root.shell }

            Text {
                visible: root.listed.length === 0
                width: parent.width
                text: root.unavailable ? "Install todoman to use this panel"
                    : root.view === "done" ? "Nothing completed yet"
                    : root.view === "overdue" ? "Nothing overdue" : "Nothing to do"
                color: root.shell.alpha(root.shell.foreground, .35)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                topPadding: Style.rowGap
            }

            Column {
                id: sectionList
                width: parent.width; spacing: Style.sm
                Repeater {
                model: root.sections
                Column {
                id: section
                required property var modelData
                width: sectionList.width; spacing: 2

                Text {
                    width: section.width
                    text: section.modelData.label
                    color: root.shell.alpha(root.shell.foreground, .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    font.letterSpacing: 1; font.bold: true
                    bottomPadding: Style.xs
                }

                Repeater {
                    model: section.modelData.items
                    Rectangle {
                        id: taskRow
                        required property var modelData
                        required property int index
                        readonly property int flatIndex: section.modelData.offset + taskRow.index
                        readonly property bool selected: taskRow.flatIndex === root.cursor
                        readonly property bool done: taskRow.modelData.completed === true
                        readonly property bool confirming: root.pendingDelete === String(taskRow.modelData.id)
                        readonly property bool editing: root.editingId === root.taskKey(taskRow.modelData)
                        function finish(commit) { root.finishEdit(taskRow.modelData, rowEditor.text, commit) }
                        onConfirmingChanged: {
                            if (taskRow.confirming) root.confirmingRow = taskRow
                            else if (root.confirmingRow === taskRow) root.confirmingRow = null
                        }
                        onEditingChanged: {
                            if (taskRow.editing) root.editingRow = taskRow
                            else {
                                rowEditor.focus = false
                                if (root.editingRow === taskRow) root.editingRow = null
                                if (root.open) taskKeys.forceActiveFocus()
                            }
                        }
                        width: section.width
                        height: (taskRow.editing ? rowEditor.height : rowText.implicitHeight) + Style.px(18)
                        radius: root.shell.rounding
                        color: taskRow.confirming
                            ? root.shell.alpha(root.shell.role("error", root.shell.foreground), .18)
                            : taskRow.selected ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .3)
                            : rowHover.hovered ? root.shell.alpha(root.shell.foreground, .07) : "transparent"

                        HoverHandler { id: rowHover }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !taskRow.editing
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                root.pendingDelete = ""
                                root.cursor = taskRow.flatIndex
                                if (mouse.button === Qt.RightButton) root.beginEdit(taskRow.modelData)
                            }
                            onDoubleClicked: root.beginEdit(taskRow.modelData)
                        }

                        Rectangle {
                            visible: taskRow.selected
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: Style.px(3); height: parent.height - Style.px(8); radius: 1
                            color: root.shell.role("act_br", root.shell.accent)
                        }

                        Text {
                            id: rowCheck
                            anchors.left: parent.left
                            anchors.leftMargin: Style.controlPaddingX * 2
                            anchors.top: parent.top; anchors.topMargin: Style.px(8)
                            text: taskRow.done ? "\u{f0133}" : "\u{f0130}"
                            color: taskRow.done ? root.shell.alpha(root.shell.foreground, .4)
                                : root.priorityColor(taskRow.modelData)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.body
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4
                                enabled: !taskRow.editing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggle(taskRow.modelData)
                            }
                        }

                        Column {
                            id: rowText
                            anchors.left: rowCheck.right; anchors.leftMargin: Style.sm
                            anchors.right: rowBin.left; anchors.rightMargin: Style.sm
                            anchors.top: parent.top; anchors.topMargin: Style.px(8)
                            visible: !taskRow.editing
                            spacing: 2
                            Text {
                                width: parent.width
                                text: taskRow.modelData.summary; elide: Text.ElideRight
                                color: taskRow.done ? root.shell.alpha(root.shell.foreground, .45)
                                    : root.priorityColor(taskRow.modelData)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                                font.strikeout: taskRow.done
                            }
                            Text {
                                visible: text !== ""
                                text: root.taskMeta(taskRow.modelData)
                                color: (root.isOverdue(taskRow.modelData) && !taskRow.done)
                                        || Number(taskRow.modelData.carries || 0) >= 3
                                    ? root.shell.role("error", root.shell.foreground)
                                    : root.shell.alpha(root.shell.foreground, .4)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            }
                        }

                        PopupField {
                            id: rowEditor
                            shell: root.shell
                            visible: taskRow.editing
                            anchors.left: rowCheck.right; anchors.leftMargin: Style.sm
                            anchors.right: rowBin.left; anchors.rightMargin: Style.sm
                            anchors.top: parent.top; anchors.topMargin: Style.px(8)
                            height: Style.controlHeight
                            onVisibleChanged: if (visible) {
                                text = String(taskRow.modelData.summary)
                                Qt.callLater(() => { rowEditor.forceActiveFocus(); rowEditor.selectAll() })
                            }
                            Keys.onReturnPressed: event => { taskRow.finish(true); event.accepted = true }
                            Keys.onEnterPressed: event => { taskRow.finish(true); event.accepted = true }
                            Keys.onEscapePressed: event => { taskRow.finish(false); event.accepted = true }
                            onActiveFocusChanged: if (!activeFocus && taskRow.editing) taskRow.finish(true)
                        }

                        Row {
                            id: rowBin
                            anchors.right: parent.right
                            anchors.rightMargin: Style.controlPaddingX
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (rowHover.hovered || taskRow.confirming) && !taskRow.editing
                            spacing: Style.sm

                            TaskAction {
                                visible: !taskRow.confirming && root.canReorder(taskRow.modelData, -1)
                                glyph: "↑"; hint: "Move up (Shift+K)"
                                onTriggered: root.reorder(taskRow.modelData, -1)
                            }
                            TaskAction {
                                visible: !taskRow.confirming && root.canReorder(taskRow.modelData, 1)
                                glyph: "↓"; hint: "Move down (Shift+J)"
                                onTriggered: root.reorder(taskRow.modelData, 1)
                            }
                            TaskAction {
                                visible: !taskRow.confirming && !taskRow.done && root.priorityIndex(taskRow.modelData) < 3
                                glyph: "▴"; hint: "Raise priority (H)"
                                tone: root.priorityColor(taskRow.modelData)
                                onTriggered: root.shiftPriority(taskRow.modelData, 1)
                            }
                            TaskAction {
                                visible: !taskRow.confirming && !taskRow.done && root.priorityIndex(taskRow.modelData) > 0
                                glyph: "▾"; hint: "Lower priority (L)"
                                tone: root.priorityColor(taskRow.modelData)
                                onTriggered: root.shiftPriority(taskRow.modelData, -1)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: taskRow.confirming ? Math.ceil(contentWidth) : Style.px(20)
                                horizontalAlignment: Text.AlignHCenter
                                text: taskRow.confirming ? "Delete" : "\u{f0a7a}"
                                color: root.shell.alpha(root.shell.role("error", root.shell.foreground),
                                    binArea.containsMouse ? 1 : .72)
                                font.family: root.shell.fontFamily
                                font.pixelSize: taskRow.confirming ? Style.caption : Style.bodySmall
                                font.bold: taskRow.confirming
                                Rectangle {
                                    anchors.top: parent.bottom; anchors.topMargin: Style.xxs
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.ceil(parent.contentWidth); height: 1
                                    visible: taskRow.confirming && binArea.containsMouse
                                    color: parent.color
                                }
                                MouseArea {
                                    id: binArea
                                    anchors.fill: parent; anchors.margins: -4
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.remove(taskRow.modelData)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: taskRow.confirming
                                text: "Cancel"
                                color: root.shell.alpha(root.shell.foreground, cancelArea.containsMouse ? .9 : .5)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                Rectangle {
                                    anchors.top: parent.bottom; anchors.topMargin: Style.xxs
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.ceil(parent.contentWidth); height: 1
                                    visible: cancelArea.containsMouse
                                    color: parent.color
                                }
                                MouseArea {
                                    id: cancelArea
                                    anchors.fill: parent; anchors.margins: -4
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pendingDelete = ""
                                }
                            }
                        }
                    }
                }
                }
                }
            }

            PopupSeparator { visible: !root.unavailable; shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                visible: !root.unavailable
                Text {
                    text: "COMPLETED · LAST 14 DAYS"
                    color: root.shell.alpha(root.shell.foreground, .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    font.letterSpacing: 1; font.bold: true
                }
                Row {
                    id: historyBars
                    width: parent.width; height: Style.px(26); spacing: Style.xs
                    Repeater {
                        model: root.history
                        Item {
                            required property var modelData
                            width: (historyBars.width - historyBars.spacing * 13) / 14
                            height: historyBars.height
                            Rectangle {
                                anchors.fill: parent; radius: Math.min(width / 3, root.shell.rounding)
                                color: root.shell.alpha(root.shell.foreground, .08)
                                border.width: parent.modelData.key === root.todayKey ? 1 : 0
                                border.color: root.shell.alpha(root.shell.foreground, .55)
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: Math.round(parent.height * parent.modelData.count / root.historyMax)
                                radius: Math.min(width / 3, root.shell.rounding)
                                color: root.shell.alpha(root.shell.foreground, .7)
                            }
                        }
                    }
                }
                Item {
                    width: parent.width; height: historyCaption.implicitHeight
                    Text {
                        id: historyCaption; anchors.left: parent.left
                        text: root.streak > 0 ? root.streak + " day streak" : "No streak yet"
                        color: root.shell.alpha(root.shell.foreground, .42)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.completedRetained + " of " + root.todos.length + " retained complete"
                        color: root.shell.alpha(root.shell.foreground, .42)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }

            Text {
                width: parent.width
                visible: !root.unavailable
                textFormat: Text.RichText
                text: "<a href=\"help\" style=\"text-decoration:none\">?</a>&nbsp; help"
                    + "&nbsp;&nbsp;&nbsp; j k&nbsp; move&nbsp;&nbsp;&nbsp; J K&nbsp; reorder"
                    + "&nbsp;&nbsp;&nbsp; space&nbsp; done&nbsp;&nbsp;&nbsp; e&nbsp; edit"
                    + "&nbsp;&nbsp;&nbsp; h&nbsp;l&nbsp;priority&nbsp;&nbsp;&nbsp; q&nbsp; add"
                linkColor: root.shell.role("act_br", root.shell.accent)
                onLinkActivated: link => { if (link === "help") root.showHelp = true }
                color: root.shell.alpha(root.shell.foreground, .3)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                topPadding: Style.sectionGap
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Column {
            id: helpColumn
            anchors.left: parent.left; anchors.right: parent.right
            spacing: Style.sm
            opacity: root.showHelp ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Style.hoverDuration } }

            PopupHero {
                shell: root.shell; icon: "󰋗"; title: "Shortcuts"
                status: "? or esc to go back"
            }
            PopupSeparator { shell: root.shell }

            HelpRow { keys: "j k  ↑ ↓"; action: "Move through the list" }
            HelpRow { keys: "J K"; action: "Move a task down or up" }
            HelpRow { keys: "space"; action: "Complete — or reopen a done one" }
            HelpRow { keys: "enter"; action: "Complete — or reopen a done one" }
            HelpRow { keys: "e"; action: "Edit the selected task" }
            HelpRow { keys: "h l  ← →"; action: "Raise or lower priority" }
            HelpRow { keys: "x  x"; action: "Delete — twice to confirm, esc to cancel" }
            HelpRow { keys: "q"; action: "Jump to the add box" }
            HelpRow { keys: "t o a d"; action: "Today · Overdue · All · Done" }
            HelpRow { keys: "tab"; action: "Cycle the views" }
            HelpRow { keys: "r"; action: "Refresh from todoman" }
            HelpRow { keys: "esc"; action: "Leave the box, cancel a delete, or close" }

            PopupSeparator { shell: root.shell }
            Text {
                text: "QUICK ADD"
                color: root.shell.alpha(root.shell.foreground, .45)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                font.letterSpacing: 1; font.bold: true
            }
            HelpRow { keys: "today  tomorrow"; action: "Also tod · tmr" }
            HelpRow { keys: "friday  next mon"; action: "Any weekday, full or short" }
            HelpRow { keys: "in 3 days"; action: "Also in 2 weeks, next week" }
            HelpRow { keys: "25 sep  sep 25"; action: "Rolls to next year once past" }
            HelpRow { keys: "2026-12-24"; action: "A plain ISO date" }
            HelpRow { keys: "5pm  at 14:30"; action: "A due time as well as a day" }
            HelpRow { keys: "+work  +home"; action: "Categories — click one to filter" }
            HelpRow { keys: "!high  p1"; action: "Priority — !medium !low, p1–p4" }
        }

    }
}

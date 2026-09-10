pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "tasks"
    contentWidth: Style.px(420)
    contentHeight: Math.max(tasksColumn.implicitHeight,
        showHelp ? helpColumn.implicitHeight : 0) + padding * 2

    property var todos: []
    property bool unavailable: false
    property string view: "today"
    property int cursor: 0
    property string pendingDelete: ""
    property bool showHelp: false

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
    readonly property var open_: todos.filter(item => item.completed !== true)
    readonly property var listed: {
        const base = view === "done" ? todos.filter(item => item.completed === true)
            : view === "all" ? open_
            : view === "overdue" ? open_.filter(item => isOverdue(item))
            : open_.filter(item => isOverdue(item) || isToday(item))
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
        if (view === "all") {
            push("LATER", rows.filter(item => !isOverdue(item) && !isToday(item)
                && dueMillis(item) >= 0))
            push("NO DATE", rows.filter(item => dueMillis(item) < 0))
        }
        return out
    }
    readonly property int dueCount: open_.filter(item => isOverdue(item) || isToday(item)).length

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
    function move(delta) {
        if (listed.length === 0) return
        cursor = Math.max(0, Math.min(listed.length - 1, cursor + delta))
        pendingDelete = ""
    }
    function cycleView(delta) {
        const at = views.indexOf(view)
        view = views[(at + delta + views.length) % views.length]
    }

    onViewChanged: { cursor = 0; pendingDelete = "" }
    onCategoryFilterChanged: { cursor = 0; pendingDelete = "" }
    onOpenChanged: {
        if (!open) {
            pendingDelete = ""
            showHelp = false
            return
        }
        view = "today"
        cursor = 0
        categoryFilter = ""
        refresh()
        taskKeys.forceActiveFocus()
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

        Keys.onPressed: event => {
            if (addField.activeFocus) return
            switch (event.key) {
            case Qt.Key_Down: case Qt.Key_J: root.move(1); break
            case Qt.Key_Up: case Qt.Key_K: root.move(-1); break
            case Qt.Key_Tab: root.cycleView(1); break
            case Qt.Key_Backtab: root.cycleView(-1); break
            case Qt.Key_T: root.view = "today"; break
            case Qt.Key_O: root.view = "overdue"; break
            case Qt.Key_A: root.view = "all"; break
            case Qt.Key_D: root.view = "done"; break
            case Qt.Key_R: root.refresh(); break
            case Qt.Key_Question: root.showHelp = !root.showHelp; break
            case Qt.Key_Q: addField.forceActiveFocus(); break
            case Qt.Key_Space:
                if (root.listed[root.cursor]) root.toggle(root.listed[root.cursor])
                break
            case Qt.Key_X:
                if (root.listed[root.cursor]) root.remove(root.listed[root.cursor])
                break
            case Qt.Key_Escape:
                if (root.showHelp) { root.showHelp = false; break }
                if (root.pendingDelete !== "") { root.pendingDelete = ""; break }
                return
            default: return
            }
            event.accepted = true
        }

        Column {
            id: tasksColumn
            anchors.left: parent.left; anchors.right: parent.right
            spacing: Style.sm
            opacity: root.showHelp ? 0 : 1
            visible: opacity > 0

            Item {
                width: parent.width
                height: hero.implicitHeight
                PopupHero {
                    id: hero
                    shell: root.shell; icon: "\u{f0132}"; title: "Tasks"
                    status: root.unavailable ? "todoman is not installed"
                        : root.dueCount === 0 ? "nothing due"
                        : root.view.toUpperCase() + "  ·  " + root.listed.length
                            + (root.listed.length === 1 ? " task" : " tasks")
                }
                Text {
                    anchors.right: parent.right; anchors.top: parent.top
                    text: "\u{f0625}"
                    color: root.shell.alpha(root.shell.foreground, helpArea.containsMouse ? .9 : .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.body
                    MouseArea {
                        id: helpArea
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.showHelp = !root.showHelp
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
                    anchors.right: addButton.left
                    anchors.rightMargin: Style.sm
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
                    Keys.onEscapePressed: taskKeys.forceActiveFocus()
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
                        width: section.width
                        height: rowText.implicitHeight + Style.px(18)
                        radius: root.shell.rounding
                        color: taskRow.confirming
                            ? root.shell.alpha(root.shell.role("error", root.shell.foreground), .18)
                            : taskRow.selected ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .3)
                            : rowHover.hovered ? root.shell.alpha(root.shell.foreground, .07) : "transparent"

                        HoverHandler { id: rowHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.pendingDelete = ""
                                root.cursor = taskRow.flatIndex
                            }
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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggle(taskRow.modelData)
                            }
                        }

                        Column {
                            id: rowText
                            anchors.left: rowCheck.right; anchors.leftMargin: Style.sm
                            anchors.right: rowBin.left; anchors.rightMargin: Style.sm
                            anchors.top: parent.top; anchors.topMargin: Style.px(8)
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
                                text: taskRow.done
                                    ? [root.completedLabel(taskRow.modelData),
                                        root.dueLabel(taskRow.modelData) === "" ? ""
                                            : "due " + root.dueLabel(taskRow.modelData)]
                                        .filter(part => part !== "").join("  ·  ")
                                    : root.dueLabel(taskRow.modelData)
                                color: root.isOverdue(taskRow.modelData) && !taskRow.done
                                    ? root.shell.role("error", root.shell.foreground)
                                    : root.shell.alpha(root.shell.foreground, .4)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            }
                        }

                        Row {
                            id: rowBin
                            anchors.right: parent.right
                            anchors.rightMargin: Style.controlPaddingX
                            anchors.verticalCenter: parent.verticalCenter
                            visible: rowHover.hovered || taskRow.confirming
                            spacing: Style.sm

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
                                font.underline: taskRow.confirming && binArea.containsMouse
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
                                font.underline: cancelArea.containsMouse
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

            Text {
                width: parent.width
                visible: !root.unavailable
                text: "?  shortcuts     j k  move     space  done / undo     q  add     t o a d  views"
                color: root.shell.alpha(root.shell.foreground, .3)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
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
            HelpRow { keys: "space"; action: "Complete — or reopen a done one" }
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

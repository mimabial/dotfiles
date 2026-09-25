pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io

// The notification centre: dunst's live state on top, and under it the archive
// that notify/archive keeps, which outlives dunst's 20-entry ring.
PopupCard {
    id: root
    popupName: "notifications"
    // Never claims Exclusive keyboard focus: held open it would pin the bar
    // surface to Exclusive (MainBar) and a click outside could not dismiss this.
    // Typed characters reach the search field through handleKey instead.
    contentWidth: Style.px(380)
    contentHeight: Style.px(520)

    property var report: ({})
    readonly property var entries: report.entries || []
    readonly property bool paused: report.paused === true
    readonly property int unread: report.unread || 0

    property bool showBody: true
    property bool showPreview: true
    // "auto" opens the picture an entry kept and otherwise focuses the sender;
    // "focus" never opens the file; "none" makes the list read-only
    property string clickAction: "auto"

    property string filter: ""
    property bool searching: false
    property double now: Date.now()
    // what counted as unread when the panel was opened; the rows stay marked
    // while it is open, rather than clearing themselves out from under the eye
    property double seenMark: -1

    function refresh() { if (!historyProc.running) historyProc.running = true }
    function act(command) { shell.run(command, root.refresh) }
    function store(args) { shell.run(["hyprshell", "notify/archive"].concat(args), root.refresh) }
    function markSeen() { store(["seen", String(Date.now())]) }

    function startSearch() { searching = true }
    function endSearch() {
        searching = false
        searchField.text = ""
        filter = ""
        resumeKeyboard()
    }

    function matches(entry) {
        if (filter === "") return true
        const needle = filter.toLowerCase()
        return [entry.app, entry.summary, entry.body].some(
            value => String(value || "").toLowerCase().indexOf(needle) >= 0)
    }

    // The heading a notification is filed under. Days, not hours: what you
    // remember about the one you are hunting for is which day it was, and a list
    // broken any finer is a list that is mostly headings.
    function dayOf(timestamp) {
        const when = new Date(timestamp)
        const today = new Date()
        const midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
        if (timestamp >= midnight) return "Today"
        if (timestamp >= midnight - 86400000) return "Yesterday"
        if (timestamp >= midnight - 6 * 86400000) return Qt.formatDateTime(when, "dddd")
        if (when.getFullYear() === today.getFullYear()) return Qt.formatDateTime(when, "d MMMM")
        return Qt.formatDateTime(when, "d MMMM yyyy")
    }

    function rebuild() {
        rows.clear()
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i]
            if (!matches(entry)) continue
            const stamp = Number(entry.ts || 0)
            rows.append({
                key: String(entry.key || ""),
                app: String(entry.app || ""),
                summary: String(entry.summary || ""),
                body: String(entry.body || ""),
                iconPath: String(entry.icon || ""),
                previewPath: String(entry.preview || ""),
                urgency: String(entry.urgency || "NORMAL"),
                timestamp: stamp,
                day: dayOf(stamp),
                fresh: root.seenMark >= 0 && stamp > root.seenMark
            })
        }
    }

    function activate(key) {
        if (clickAction === "none" || !key) return
        store(clickAction === "focus" ? ["--focus-only", key] : [key])
        shell.closePopup()
    }
    function removeRow(key) {
        if (!key) return
        for (let i = 0; i < rows.count; i++)
            if (rows.get(i).key === key) { rows.remove(i); break }
        store(["remove", key])
    }
    function clearAll() {
        rows.clear()
        store(["clear"])
    }

    function handleKey(event) {
        if (searching) {
            if (event.key === Qt.Key_Escape) { endSearch(); return true }
            if (event.key === Qt.Key_Backspace) {
                searchField.text = searchField.text.slice(0, -1); return true
            }
            if (event.text && event.text.length === 1 && event.text >= " ") {
                searchField.text += event.text; return true
            }
            return defaultKey(event)
        }
        // "/" is the only key that opens the search, so the list stays navigable
        if (event.text === "/") { startSearch(); return true }
        if (event.key === Qt.Key_Delete && rows.count > 0 && cursorIndex >= 0) {
            removeRow(rows.get(cursorIndex).key); return true
        }
        return defaultKey(event)
    }

    onFilterChanged: rebuild()
    onEntriesChanged: rebuild()
    onOpenChanged: {
        if (!open) {
            endSearch()
            seenMark = -1
            return
        }
        refresh()
    }

    ListModel { id: rows }

    property Process historyProc: Process {
        command: ["hyprshell", "notify/history"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
            root.now = Date.now()
            // the watermark is read before it is moved, so this pass still knows
            // which rows arrived while the panel was shut
            if (root.open && root.seenMark < 0) {
                root.seenMark = Number(root.report.seen || 0)
                root.rebuild()
                root.markSeen()
            }
        } }
    }
    property Timer poll: Timer { interval: 4000; running: root.open; repeat: true; onTriggered: root.refresh() }

    // an inline header action, labelled by its own tooltip rather than a legend
    component HeaderAction: Rectangle {
        id: headerAction
        required property string glyph
        required property string hint
        property color glyphColor: root.shell.foreground
        signal triggered
        width: Style.px(26); height: Style.px(26); radius: root.shell.rounding
        color: actionArea.containsMouse ? root.shell.hoverFill(3) : "transparent"
        Text {
            anchors.centerIn: parent
            text: headerAction.glyph
            color: headerAction.glyphColor
            font.family: root.shell.fontFamily; font.pixelSize: Style.title
        }
        MouseArea {
            id: actionArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: headerAction.triggered()
        }
        BarTooltip { shell: root.shell; anchorItem: headerAction; text: headerAction.hint; hovered: actionArea.containsMouse }
    }

    Column {
        id: notifyColumn
        anchors.fill: parent; spacing: Style.sm

        Item {
            width: parent.width
            implicitHeight: Math.max(hero.implicitHeight, headerActions.implicitHeight)

            PopupHero {
                id: hero
                anchors.left: parent.left
                anchors.right: headerActions.left; anchors.rightMargin: Style.xs
                shell: root.shell
                title: "Notifications"
                status: root.paused
                    ? "do not disturb" + (root.report.waiting > 0 ? " · " + root.report.waiting + " waiting" : "")
                    : root.unread > 0 ? root.unread + " new" : "on"
            }
            Row {
                id: headerActions
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                HeaderAction {
                    glyph: "\u{f0349}"
                    hint: "Search these notifications  ( / )"
                    glyphColor: root.searching ? root.shell.accent : root.shell.foreground
                    onTriggered: root.searching ? root.endSearch() : root.startSearch()
                }
                HeaderAction {
                    glyph: root.paused ? "\u{f009b}" : "\u{f009a}"
                    hint: root.paused ? "Allow notifications" : "Silence notifications"
                    glyphColor: root.paused ? root.shell.accent : root.shell.foreground
                    onTriggered: root.act(["hyprshell", "notify/notifications", "--toggle"])
                }
                HeaderAction {
                    glyph: "\u{f039f}"
                    hint: "Show the most recent notification again"
                    onTriggered: root.act(["dunstctl", "history-pop"])
                }
                HeaderAction {
                    glyph: "\u{f0a7a}"
                    hint: "Clear the archive"
                    onTriggered: root.clearAll()
                }
            }
        }

        Rectangle {
            visible: root.searching
            width: parent.width; height: visible ? Style.px(28) : 0
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .25)
            border.width: 1
            border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .5)
            TextField {
                id: searchField
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                height: Style.px(20)
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Search — Esc leaves, Esc again closes"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
            }
        }

        PopupSeparator { shell: root.shell }

        Text {
            visible: rows.count === 0
            width: parent.width
            text: root.filter !== "" ? "No match" : "Nothing kept yet"
            color: root.shell.alpha(root.shell.foreground, .5)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        ListView {
            id: entryList
            width: parent.width
            height: Math.max(0, parent.height - y)
            spacing: Style.sm
            clip: true
            model: rows
            currentIndex: root.cursorIndex
            ScrollBar.vertical: PopupScrollBar { shell: root.shell }

            section.property: "day"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                required property string section
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: sectionLabel.implicitHeight + Style.sm
                PopupSection {
                    id: sectionLabel
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    shell: root.shell
                    text: parent.section.toUpperCase()
                }
            }

            delegate: NotificationEntry {
                required property var model
                required property int index
                shell: root.shell
                app: model.app
                summary: model.summary
                body: model.body
                iconPath: model.iconPath
                previewPath: model.previewPath
                urgency: model.urgency
                timestamp: model.timestamp
                unread: model.fresh
                now: root.now
                showBody: root.showBody
                showPreview: root.showPreview
                onClicked: root.activate(model.key)
                onRemoveRequested: root.removeRow(model.key)
                // the pointer moves the same cursor the keyboard does, so one
                // row is ever focused
                onHoveredChanged: if (hovered) root.cursorIndex = index
            }
        }
    }
}

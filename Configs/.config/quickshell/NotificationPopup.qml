pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "CalendarMath.js" as CalendarMath

// The notification centre: dunst's live state on top, and under it the archive
// that notify/archive keeps, which outlives dunst's 20-entry ring.
PopupCard {
    id: root
    popupName: "notifications"
    keyboardHint: searching ? "Type search · ↑↓ move · Enter select · Esc" : "↑↓ move · Enter select · / search · Del · Esc"
    property Component calendarPane: null
    property bool calendarLoaded: false
    readonly property bool groupsByApp: calendarPane !== null
    property string expandedApp: ""
    property var appGroupSizes: ({})
    readonly property int calendarPaneWidth: Style.px(300)
    readonly property int notificationPaneWidth: Style.px(380) - padding * 2
    contentWidth: notificationPaneWidth + padding * 2 + (calendarPane ? calendarPaneWidth + Style.sectionGap * 2 + 1 : 0)
    contentHeight: Math.max(Style.px(520), (calendarLoader.item as Item)?.implicitHeight ?? 0) + (calendarPane ? padding * 2 : 0)

    readonly property var report: Notifications.report
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

    function refresh() { Notifications.refresh() }
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
        if (timestamp >= midnight - CalendarMath.MS_PER_DAY) return "Yesterday"
        if (timestamp >= midnight - 6 * CalendarMath.MS_PER_DAY) return Qt.formatDateTime(when, "dddd")
        if (when.getFullYear() === today.getFullYear()) return Qt.formatDateTime(when, "d MMMM")
        return Qt.formatDateTime(when, "d MMMM yyyy")
    }

    function collapsedByApp(list) {
        const groups = new Map()
        for (const entry of list) {
            const app = String(entry.app || "")
            if (!groups.has(app)) groups.set(app, [])
            groups.get(app).push(entry)
        }
        const sizes = {}, listed = []
        groups.forEach((members, app) => {
            sizes[app] = members.length
            listed.push(...(app === expandedApp ? members : members.slice(0, 1)))
        })
        appGroupSizes = sizes
        return listed
    }

    function rebuild() {
        rows.clear()
        const shown = entries.filter(matches)
        for (const entry of groupsByApp ? collapsedByApp(shown) : shown) {
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
        shell.run(["hyprshell", "notify/open"].concat(clickAction === "focus" ? ["--focus-only", key] : [key]))
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
        if (event.key === Qt.Key_Delete) {
            const row = navigableRows[cursorIndex]
            if (row instanceof NotificationEntry) row.removeRequested()
            return true
        }
        return defaultKey(event)
    }

    onFilterChanged: rebuild()
    onEntriesChanged: rebuild()
    onExpandedAppChanged: rebuild()
    onOpenChanged: {
        if (!open) {
            endSearch()
            expandedApp = ""
            seenMark = -1
            return
        }
        if (calendarPane) calendarLoaded = true
        refresh()
    }

    ListModel { id: rows }

    Connections {
        target: Notifications
        function onReportChanged() {
            root.now = Date.now()
            if (root.open && root.seenMark < 0) {
                root.seenMark = Number(root.report.seen || 0)
                root.rebuild()
                root.markSeen()
            }
        }
    }

    Column {
        id: notifyColumn
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: root.notificationPaneWidth; spacing: Style.sectionGap

        Item {
            visible: !root.calendarPane
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
                PopupIconButton {
                    shell: root.shell
                    glyph: "\u{f0349}"
                    hint: "Search these notifications  ( / )"
                    glyphColor: root.searching ? root.shell.accent : root.shell.foreground
                    onClicked: root.searching ? root.endSearch() : root.startSearch()
                }
                PopupIconButton {
                    shell: root.shell
                    glyph: root.paused ? "\u{f009b}" : "\u{f009a}"
                    hint: root.paused ? "Allow notifications" : "Silence notifications"
                    glyphColor: root.paused ? root.shell.accent : root.shell.foreground
                    onClicked: root.act(["hyprshell", "notify/notifications", "--toggle"])
                }
                PopupIconButton {
                    shell: root.shell
                    glyph: "\u{f039f}"
                    hint: "Show the most recent notification again"
                    onClicked: root.act(["dunstctl", "history-pop"])
                }
                PopupIconButton {
                    shell: root.shell
                    glyph: "\u{f0a7a}"
                    hint: "Clear the archive"
                    onClicked: root.clearAll()
                }
            }
        }

        Rectangle {
            visible: root.searching
            width: parent.width; height: Style.controlHeight
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .25)
            border.width: 1
            border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .5)
            TextField {
                id: searchField
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Search — Esc leaves, Esc again closes"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
            }
        }

        Column {
            width: parent.width; spacing: Style.sm
            visible: root.calendarPane !== null && Media.hasMedia
            PopupRow {
                width: parent.width; shell: root.shell; iconSource: Media.artUrl; icon: Media.artUrl ? "" : "󰝚"
                title: Media.title; detail: Media.artist; onClicked: root.shell.togglePopup("media")
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                PopupIconButton { shell: root.shell; glyph: "󰒮"; hint: "Previous"; enabled: !!Media.player?.canGoPrevious; onClicked: Media.previous() }
                PopupIconButton { shell: root.shell; glyph: Media.player?.isPlaying ? "󰏤" : "󰐊"; hint: Media.player?.isPlaying ? "Pause" : "Play"; onClicked: Media.playPause() }
                PopupIconButton { shell: root.shell; glyph: "󰒭"; hint: "Next"; enabled: Media.canNext(); onClicked: Media.next() }
            }
        }
        PopupSeparator { shell: root.shell; visible: !root.calendarPane }

        Text {
            visible: rows.count === 0
            width: parent.width
            text: root.filter !== "" ? "No match" : root.calendarPane ? "No Notifications" : "Nothing kept yet"
            color: root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        ListView {
            id: entryList
            width: parent.width
            height: Math.max(0, parent.height - y - (root.calendarPane ? dateFooter.height + Style.sectionGap : 0))
            spacing: Style.sm
            clip: true
            model: rows
            ScrollBar.vertical: PopupScrollBar { shell: root.shell }

            section.property: root.groupsByApp ? "app" : "day"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                id: sectionHeader
                required property string section
                readonly property int groupSize: root.appGroupSizes[section] || 0
                readonly property bool stacked: root.groupsByApp && groupSize > 1
                readonly property bool expanded: root.expandedApp === section
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: stacked ? groupToggle.implicitHeight + Style.sm
                    : root.groupsByApp ? 0 : sectionLabel.implicitHeight + Style.sm
                PopupSection {
                    id: sectionLabel
                    visible: !root.groupsByApp
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    shell: root.shell
                    text: sectionHeader.section.toUpperCase()
                }
                PopupRow {
                    id: groupToggle
                    visible: sectionHeader.stacked
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    shell: root.shell
                    title: sectionHeader.section
                    value: sectionHeader.groupSize + "  " + (sectionHeader.expanded ? "\u{f0143}" : "\u{f0140}")
                    onClicked: root.expandedApp = sectionHeader.expanded ? "" : sectionHeader.section
                }
            }

            delegate: NotificationEntry {
                id: notificationEntry
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
                onHoveredChanged: if (hovered) root.selectRow(notificationEntry)
            }
        }
        Item {
            id: dateFooter
            visible: root.calendarPane !== null
            width: parent.width; implicitHeight: clearButton.implicitHeight
            PopupTab { id: clearButton; anchors.right: parent.right; shell: root.shell; text: "Clear"; enabled: root.entries.length > 0; onClicked: root.clearAll() }
        }
    }
    Rectangle {
        visible: root.calendarPane !== null
        x: root.notificationPaneWidth + Style.sectionGap; width: 1; height: parent.height
        color: root.shell.alpha(root.shell.foreground, Style.hoverFillAlpha)
    }
    Loader {
        id: calendarLoader
        active: root.calendarPane !== null && root.calendarLoaded
        anchors.right: parent.right; anchors.top: parent.top
        width: root.calendarPaneWidth
        sourceComponent: root.calendarPane
    }
}

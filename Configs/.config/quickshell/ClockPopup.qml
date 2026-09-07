pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io

PopupCard {
    id: root
    popupName: "clock"
    readonly property int calendarWidth: Style.px(440) - padding * 2
    readonly property int agendaWidth: Style.px(520)
    readonly property int choiceColumn: Style.px(84)
    readonly property int paneGap: Style.px(16)
    property bool expanded: false
    contentWidth: calendarWidth + padding * 2 + (expanded ? agendaWidth + paneGap : 0)
    contentHeight: Math.max(calendar.implicitHeight, expanded ? agendaContent.implicitHeight : 0) + Style.px(32)

    // bound, not sampled: the panel rolls over if left open past midnight
    readonly property date today: root.shell.clock.date
    property date viewDate: new Date(today.getFullYear(), today.getMonth(), 1)

    // Locale.Sunday === 0. The locale decides unless overridden; en_US says
    // Sunday, which is not what everyone wants.
    property int weekStartOverride: -1
    readonly property int weekStart: weekStartOverride >= 0 ? weekStartOverride : Qt.locale().firstDayOfWeek
    readonly property string otherWeekStartName: Qt.locale().dayName(weekStart === 1 ? 0 : 1, Locale.LongFormat)

    property date cursor: today
    readonly property var weekdays: {
        const names = []
        for (let day = 0; day < 7; day++)
            names.push(Qt.locale().dayName((weekStart + day) % 7, Locale.ShortFormat).toUpperCase())
        return names
    }
    readonly property int leading: {
        const first = new Date(viewDate.getFullYear(), viewDate.getMonth(), 1).getDay()
        return (first - weekStart + 7) % 7
    }

    readonly property int weekColumn: 26
    readonly property real cellWidth: (calendar.width - weekColumn - 14) / 7

    function moveMonth(delta) { viewDate = new Date(viewDate.getFullYear(), viewDate.getMonth() + delta, 1) }
    function moveYear(delta) { viewDate = new Date(viewDate.getFullYear() + delta, viewDate.getMonth(), 1) }
    function goToToday() {
        cursor = today
        viewDate = new Date(today.getFullYear(), today.getMonth(), 1)
    }
    function moveDay(days) {
        const next = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + days)
        cursor = next
        // follow the cursor when it leaves the month on screen
        if (next.getFullYear() !== viewDate.getFullYear() || next.getMonth() !== viewDate.getMonth())
            viewDate = new Date(next.getFullYear(), next.getMonth(), 1)
    }
    property var storedSettings: ({})
    property bool settingsLoaded: false
    function persist() {
        if (!settingsLoaded) return
        const saved = storedSettings || ({})
        saved.weekStart = weekStartOverride
        saved.agendaMode = agendaMode
        storedSettings = saved
        store.setText(JSON.stringify(saved))
    }
    function toggleWeekStart() {
        weekStartOverride = weekStart === 1 ? 0 : 1
        persist()
    }
    function dateAt(index) { return new Date(viewDate.getFullYear(), viewDate.getMonth(), index - leading + 1) }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }

    // ISO-8601: week 1 is the one holding the first Thursday of the year
    function isoWeek(date) {
        const day = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
        day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7) + 3)
        const firstThursday = new Date(Date.UTC(day.getUTCFullYear(), 0, 4))
        firstThursday.setUTCDate(firstThursday.getUTCDate() - ((firstThursday.getUTCDay() + 6) % 7) + 3)
        return 1 + Math.round((day - firstThursday) / 604800000)
    }

    property var agenda: ({})
    property var monthDays: ({})
    property var weekDays: ({})
    property string agendaMode: "day"
    function dateFromIso(iso) { return new Date(String(iso) + "T12:00:00") }
    function weekStartDate(date) {
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate())
        start.setDate(start.getDate() - ((start.getDay() - weekStart + 7) % 7))
        return start
    }
    readonly property string weekAnchor: isoDay(weekStartDate(cursor))
    readonly property var weekKeys: {
        const start = weekStartDate(cursor)
        const keys = []
        for (let offset = 0; offset < 7; offset++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + offset)
            keys.push(isoDay(day))
        }
        return keys
    }
    readonly property string weekHeading: {
        const keys = weekKeys
        if (keys.length !== 7) return ""
        const first = dateFromIso(keys[0])
        const last = dateFromIso(keys[6])
        return "W" + isoWeek(first) + "  ·  " + Qt.formatDate(first, "MMM d")
            + " – " + Qt.formatDate(last, "MMM d, yyyy")
    }
    function eventsOn(iso) { return weekDays[String(iso)] || [] }
    function relativeDayLabel(iso) {
        const today = isoDay(root.today)
        if (iso === today) return "Today"
        const day = dateFromIso(iso)
        const gap = Math.round((day - dateFromIso(today)) / 86400000)
        return gap === 1 ? "Tomorrow" : gap === -1 ? "Yesterday" : ""
    }
    function isWeekendIso(iso) {
        const weekday = dateFromIso(iso).getDay()
        return weekday === 0 || weekday === 6
    }
    function chipColor(event) {
        return calendarColor(String(event.calendar || ""),
            root.shell.role("act_br", root.shell.accent))
    }
    readonly property var agendaEvents: agenda.events || []

    property var calendars: ({})
    property string defaultCalendar: ""
    property var locations: []
    property var placeResults: []
    property string locationQuery: ""
    property int locationIndex: 0
    property bool locationDismissed: false
    onLocationQueryChanged: {
        locationIndex = 0
        locationDismissed = false
        placesDebounce.restart()
    }
    readonly property var locationSuggestions: {
        const typed = String(locationQuery)
        const prefix = typed.toLowerCase()
        const mine = prefix === ""
            ? [] : locations.filter(known => String(known).toLowerCase().startsWith(prefix))
        const out = []
        const seen = ({})
        for (const candidate of mine.concat(placeResults)) {
            const value = String(candidate)
            const key = value.toLowerCase()
            if (value === "" || value === typed || seen[key] === true) continue
            seen[key] = true
            out.push(value)
        }
        return out.slice(0, 6)
    }
    property Timer placesDebounce: Timer {
        interval: 350
        onTriggered: {
            if (root.locationQuery.length < 3) {
                root.placeResults = []
                return
            }
            root.placesProc.running = false
            root.placesProc.command = ["hyprshell", "calendar/places", root.locationQuery]
            root.placesProc.running = true
        }
    }
    property Process placesProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.placeResults = JSON.parse(text) || [] } catch (error) { root.placeResults = [] }
        } }
    }
    function clearLocationSearch() {
        placesDebounce.stop()
        placesProc.running = false
        placeResults = []
        locationQuery = ""
        locationIndex = 0
        locationDismissed = false
    }
    function calendarOf(event) { return calendars[String(event.calendar || "")] || ({}) }
    function isReadonly(event) { return calendarOf(event).readonly === true }
    function foreignCalendar(event) {
        const name = String(event.calendar || "")
        return name === defaultCalendar ? "" : name
    }
    readonly property var khalColorIndex: ({
        "black": 0, "dark red": 1, "dark green": 2, "brown": 3,
        "dark blue": 4, "dark magenta": 5, "dark cyan": 6, "white": 7,
        "dark gray": 8, "light red": 9, "light green": 10, "yellow": 11,
        "light blue": 12, "light magenta": 13, "light cyan": 14, "light gray": 15
    })
    function declaredColor(name) {
        const declared = String((calendars[String(name)] || {}).color || "").trim().toLowerCase()
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/.test(declared)) return declared
        const named = khalColorIndex[declared]
        if (named !== undefined) return root.shell.role("c" + named, root.shell.accent)
        if (/^\d{1,3}$/.test(declared) && Number(declared) < 16)
            return root.shell.role("c" + Number(declared), root.shell.accent)
        return ""
    }
    readonly property var calendarRoles: ["c1", "c2", "c3", "c4", "c5", "c6"]
    function calendarColor(name, fallback) {
        const declared = declaredColor(name)
        if (declared !== "") return declared
        if (name === "" || name === defaultCalendar) return fallback
        let hash = 0
        for (let index = 0; index < name.length; index++)
            hash = (hash * 31 + name.charCodeAt(index)) >>> 0
        return root.shell.role(calendarRoles[hash % calendarRoles.length], root.shell.accent)
    }
    function eventColor(event) {
        return calendarColor(String(event.calendar || ""),
            root.shell.alpha(root.shell.foreground, .55))
    }

    function dayEntry(date) { return monthDays[isoDay(date)] || ({}) }
    function timedCalendars(date) { return dayEntry(date).timed || [] }
    function dayTint(date) {
        const marks = dayEntry(date).allDay || []
        return marks.length === 0 ? root.shell.foreground
            : calendarColor(String(marks[0]), root.shell.role("act_br", root.shell.accent))
    }

    function isoDay(date) { return Qt.formatDate(date, "yyyy-MM-dd") }
    function loadAgenda() {
        if (!open) return
        dayProc.running = false
        dayProc.command = ["hyprshell", "calendar/agenda", "--day", isoDay(cursor)]
        dayProc.running = true
    }
    function loadMonth() {
        if (!open) return
        monthProc.running = false
        monthProc.command = ["hyprshell", "calendar/agenda", "--month", Qt.formatDate(viewDate, "yyyy-MM")]
        monthProc.running = true
    }
    function loadWeek() {
        if (!open || agendaMode !== "week") return
        weekProc.running = false
        weekProc.command = ["hyprshell", "calendar/agenda", "--week", weekAnchor]
        weekProc.running = true
    }
    onWeekAnchorChanged: loadWeek()
    onAgendaModeChanged: {
        if (agendaMode === "week") expanded = true
        loadWeek()
        persist()
    }
    property bool composing: false
    // khal's own vocabulary, so the form maps straight onto the CLI
    readonly property var alarmChoices: [
        { label: "None", value: "" }, { label: "Start", value: "0m" },
        { label: "10m", value: "10m" }, { label: "1h", value: "1h" },
        { label: "1d", value: "1d" }
    ]
    readonly property var repeatChoices: [
        { label: "Never", value: "" }, { label: "Day", value: "daily" },
        { label: "Week", value: "weekly" }, { label: "Month", value: "monthly" },
        { label: "Year", value: "yearly" }
    ]
    property bool composeAllDay: false
    property string composeAlarm: ""
    property string composeRepeat: ""
    property string composeCalendar: ""
    readonly property var writableCalendars: {
        const out = []
        for (const name in calendars)
            if (calendars[name].readonly !== true) out.push(name)
        out.sort()
        return out
    }
    signal saveRequested()
    property string editingUid: ""
    property var editingValues: ({})
    // khal writes alarms as an ISO duration; map back to the chip values
    function alarmChoiceFor(trigger) {
        const map = { "-PT0S": "0m", "PT0S": "0m", "-PT10M": "10m", "-PT1H": "1h", "-P1D": "1d" }
        return map[String(trigger)] || ""
    }
    function isoFromRaw(raw) {
        const text = String(raw)
        if (text.length < 8) return ""
        return text.slice(0, 4) + "-" + text.slice(4, 6) + "-" + text.slice(6, 8)
    }
    function timeFromRaw(raw) {
        const text = String(raw)
        const at = text.indexOf("T")
        return at < 0 ? "" : text.slice(at + 1, at + 3) + ":" + text.slice(at + 3, at + 5)
    }
    function openEvent(event) {
        const uid = String(event.uid || "")
        if (!uid) return
        showProc.running = false
        showProc.command = ["hyprshell", "calendar/agenda", "--show", uid]
        root.pendingShowUid = uid
        root.pendingShowCalendar = String(event.calendar || "")
        root.pendingShowReadonly = root.isReadonly(event)
        showProc.running = true
    }
    property string pendingShowUid: ""
    property string pendingShowCalendar: ""
    property bool pendingShowReadonly: false
    property Process showProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            if (payload.error) { root.composeError = String(payload.error); return }
            const lastDay = root.isoFromRaw(payload.endRaw)
            // an all-day DTEND is exclusive, so step it back for display
            const endDay = payload.allDay === true ? root.previousDay(lastDay) : lastDay
            const values = {
                title: String(payload.title || ""),
                start: root.timeFromRaw(payload.startRaw),
                end: root.timeFromRaw(payload.endRaw),
                endDay: endDay,
                location: String(payload.location || ""),
                description: String(payload.description || "")
            }
            if (root.pendingShowReadonly) {
                values.calendar = root.pendingShowCalendar
                values.allDay = payload.allDay === true
                values.repeat = String(payload.repeat || "")
                values.alarm = root.alarmChoiceFor(payload.alarm)
                root.detailValues = values
                root.composeError = ""
                root.detailing = true
                return
            }
            root.editingUid = root.pendingShowUid
            root.composeCalendar = root.pendingShowCalendar
            root.composeAllDay = payload.allDay === true
            root.composeRepeat = String(payload.repeat || "")
            root.composeAlarm = root.alarmChoiceFor(payload.alarm)
            root.editingValues = values
            root.composeError = ""
            root.composing = true
        } }
    }
    function previousDay(iso) {
        if (!iso) return ""
        const date = new Date(iso + "T12:00:00")
        date.setDate(date.getDate() - 1)
        return isoDay(date)
    }
    function startCompose() {
        clearLocationSearch()
        detailing = false
        editingUid = ""
        editingValues = ({})
        composeError = ""
        composeAllDay = false
        composeAlarm = ""
        composeRepeat = ""
        composeCalendar = defaultCalendar
        composing = true
    }
    function cancelCompose() {
        clearLocationSearch()
        composing = false; editingUid = ""; editingValues = ({}); composeError = ""
        closeDetail()
    }
    property bool detailing: false
    property var detailValues: ({})
    readonly property bool showingCard: composing || detailing
    function closeDetail() { detailing = false; detailValues = ({}) }
    function detailWhen() {
        if (detailValues.allDay === true) {
            const last = String(detailValues.endDay || "")
            return last !== "" && last !== isoDay(cursor) ? "All day, until " + last : "All day"
        }
        const start = String(detailValues.start || "")
        const end = String(detailValues.end || "")
        if (start === "") return ""
        return end !== "" ? start + " – " + end : start
    }
    property string composeError: ""
    // an untouched masked field still carries its separators (":" or "-  -"),
    // so "has the user typed anything" means "contains a digit"
    function fieldValue(text) {
        const packed = String(text).replace(/\s/g, "")
        return /\d/.test(packed) ? packed : ""
    }
    function saveEvent(fields) {
        const title = String(fields.title).trim()
        if (title === "") {
            composeError = "A title is required"
            return
        }
        const timed = /^\d{1,2}:\d{2}$/
        const dated = /^\d{4}-\d{2}-\d{2}$/
        const startText = fieldValue(fields.start)
        const endText = fieldValue(fields.end)
        const endDay = fieldValue(fields.endDay)

        if (endDay !== "" && !dated.test(endDay)) {
            composeError = "Last day must look like 2026-08-18"
            return
        }
        if (endDay !== "" && endDay < isoDay(cursor)) {
            composeError = "Last day is before the first"
            return
        }
        const spansDays = endDay !== "" && endDay !== isoDay(cursor)

        if (!composeAllDay) {
            if (startText === "" && endText === "") {
                composeError = "Set a start time, or switch on All day"
                return
            }
            if (startText === "") {
                composeError = "An end time needs a start time"
                return
            }
            if (!timed.test(startText)) {
                composeError = "Start time must look like 09:00"
                return
            }
            if (endText !== "") {
                if (!timed.test(endText)) {
                    composeError = "End time must look like 10:00"
                    return
                }
                if (!spansDays && endText <= startText) {
                    composeError = "Ends before it starts \u2014 set Last day for overnight"
                    return
                }
            }
        }

        const args = ["--add", "--day", isoDay(cursor), "--title", title]
        if (!composeAllDay) {
            args.push("--start", startText)
            if (endText !== "") args.push("--end", endText)
        }
        if (spansDays) args.push("--end-day", endDay)
        const where = String(fields.location).trim()
        if (where !== "") args.push("--location", where)
        const notes = String(fields.description).trim()
        if (notes !== "") args.push("--description", notes)
        if (composeAlarm !== "") args.push("--alarm", composeAlarm)
        if (composeRepeat !== "") args.push("--repeat", composeRepeat)
        if (composeCalendar !== "") args.push("--calendar", composeCalendar)

        if (editingUid !== "") args.push("--delete", editingUid)

        composeError = ""
        addProc.running = false
        addProc.command = ["hyprshell", "calendar/agenda"].concat(args)
        addProc.running = true
    }

    function deleteEvent(uid) {
        if (!uid) return
        deleteProc.running = false
        deleteProc.command = ["hyprshell", "calendar/agenda", "--delete", String(uid), "--day", isoDay(cursor)]
        deleteProc.running = true
    }
    property Process deleteProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.agenda = JSON.parse(text) || ({}) } catch (error) { root.loadAgenda() }
            root.loadMonth()
        } }
    }

    property Process addProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            if (payload.error) {
                root.composeError = String(payload.error)
                return
            }
            root.composeError = ""
            root.composing = false
            root.editingUid = ""
            root.agenda = payload
            root.loadMonth()
        } }
    }
    property Timer agendaSettle: Timer { interval: 400; onTriggered: { root.loadAgenda(); root.loadMonth() } }

    onCursorChanged: { cancelCompose(); loadAgenda() }
    onViewDateChanged: loadMonth()

    property Process dayProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.agenda = JSON.parse(text) || ({}) } catch (error) { root.agenda = ({}) }
        } }
    }
    property Process monthProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.monthDays = (JSON.parse(text) || ({})).days || ({}) } catch (error) { root.monthDays = ({}) }
        } }
    }
    property Process weekProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.weekDays = (JSON.parse(text) || ({})).days || ({}) } catch (error) { root.weekDays = ({}) }
        } }
    }
    property Process calendarsProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            root.calendars = payload.calendars || ({})
            root.defaultCalendar = String(payload.default || "")
            root.locations = payload.locations || []
        } }
    }
    function loadCalendars() {
        calendarsProc.running = false
        calendarsProc.command = ["hyprshell", "calendar/agenda", "--calendars"]
        calendarsProc.running = true
    }

    component FieldLabel: Text {
        color: root.shell.alpha(root.shell.foreground, .45)
        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        font.letterSpacing: 1; font.bold: true
    }
    component FormField: PopupField {
        shell: root.shell
        Keys.onEscapePressed: root.cancelCompose()
        onSubmitted: root.saveRequested()
    }
    component Chip: Rectangle {
        property alias text: chipText.text
        property bool selected: false
        signal picked
        implicitWidth: chipText.implicitWidth + Style.controlPaddingX * 2.5
        implicitHeight: Style.px(22)
        radius: root.shell.rounding
        color: selected ? root.shell.alpha(root.shell.role("act_br", root.shell.accent), .35)
            : chipArea.containsMouse ? root.shell.alpha(root.shell.foreground, .1) : "transparent"
        border.width: 1
        border.color: root.shell.alpha(root.shell.foreground, selected ? .4 : .16)
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Text {
            id: chipText
            anchors.centerIn: parent
            color: root.shell.alpha(root.shell.foreground, parent.selected ? 1 : .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.picked()
        }
    }

    component FormArea: ScrollView {
        property alias text: area.text
        property alias placeholderText: area.placeholderText
        property int lines: 5
        implicitHeight: Math.round(area.font.pixelSize * 1.4 * lines) + Style.controlPaddingY * 2
        clip: true
        background: Rectangle {
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.foreground, .06)
            border.width: 1
            border.color: root.shell.alpha(root.shell.foreground, area.activeFocus ? .45 : .18)
        }
        TextArea {
            id: area
            wrapMode: TextArea.Wrap
            leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
            topPadding: Style.controlPaddingY; bottomPadding: Style.controlPaddingY
            color: root.shell.foreground
            placeholderTextColor: root.shell.alpha(root.shell.foreground, .28)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            background: null
            Keys.onEscapePressed: root.cancelCompose()
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && (event.modifiers & Qt.ControlModifier)) {
                        root.saveRequested()
                        event.accepted = true
                }
            }

        }
    }

    component FormButton: Rectangle {
        property alias text: buttonText.text
        property bool primary: false
        signal activated
        implicitWidth: buttonText.implicitWidth + Style.controlPaddingX * 3
        implicitHeight: Style.px(24)
        radius: root.shell.rounding
        opacity: enabled ? 1 : .4
        color: primary
            ? root.shell.alpha(root.shell.role("act_br", root.shell.accent), buttonArea.containsMouse ? .5 : .3)
            : buttonArea.containsMouse ? root.shell.alpha(root.shell.foreground, .12) : "transparent"
        border.width: 1
        border.color: root.shell.alpha(root.shell.foreground, primary ? .4 : .22)
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Text {
            id: buttonText
            anchors.centerIn: parent
            color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent; enabled: parent.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    onOpenChanged: {
        if (open) {
            expanded = agendaMode === "week"
            goToToday()
            loadCalendars(); loadAgenda(); loadMonth(); loadWeek()
        } else cancelCompose()
    }

    property FileView store: FileView {
        path: root.shell.home + "/.local/state/quickshell/clock.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text()) || ({})
                root.storedSettings = saved
                root.weekStartOverride = saved.weekStart !== undefined ? saved.weekStart : -1
                root.agendaMode = saved.agendaMode === "week" ? "week" : "day"
            } catch (error) {
                root.storedSettings = ({})
                root.weekStartOverride = -1
            }
            root.settingsLoaded = true
        }
    }

    component NavButton: Text {
        required property string glyph
        property real size: Style.display
        text: glyph
        color: root.shell.alpha(root.shell.foreground, mouse.containsMouse ? 1 : .75)
        font.family: root.shell.fontFamily; font.pixelSize: size
        signal activated
        MouseArea { id: mouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: parent.activated() }
    }

    Row {
        anchors.fill: parent
        spacing: root.paneGap
        layoutDirection: root.position === "right" ? Qt.RightToLeft : Qt.LeftToRight

    Column {
        id: calendar
        width: root.calendarWidth
        spacing: Style.px(14)
        focus: !root.showingCard

        Keys.onPressed: event => {
            if (root.composing) return
            switch (event.key) {
            case Qt.Key_Left:     root.moveDay(-1); break
            case Qt.Key_Right:    root.moveDay(1); break
            case Qt.Key_Up:       root.moveDay(-7); break
            case Qt.Key_Down:     root.moveDay(7); break
            case Qt.Key_PageUp:   event.modifiers & Qt.ShiftModifier ? root.moveYear(-1) : root.moveMonth(-1); break
            case Qt.Key_PageDown: event.modifiers & Qt.ShiftModifier ? root.moveYear(1) : root.moveMonth(1); break
            case Qt.Key_Home:     root.goToToday(); break
            case Qt.Key_W:        root.toggleWeekStart(); break
            default: return
            }
            event.accepted = true
        }

        Text {
            width: parent.width; text: "󰃭  " + Qt.formatDate(root.today, "MMMM d")
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.displayLarge; font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Item {
            id: yearBar
            width: parent.width; height: Style.px(18)
            readonly property real progress: (root.today - new Date(root.today.getFullYear(), 0, 1)) / (new Date(root.today.getFullYear() + 1, 0, 1) - new Date(root.today.getFullYear(), 0, 1))

            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.today.getFullYear(); color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.floor(yearBar.progress * 100) + "%"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: Style.px(42); anchors.rightMargin: Style.px(34); anchors.verticalCenter: parent.verticalCenter; height: Style.px(5); radius: 3; color: root.shell.alpha(root.shell.foreground, .12); Rectangle { width: parent.width * yearBar.progress; height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) } }
        }

        Item {
            width: parent.width; height: monthGrid.implicitHeight

            // beside the day rows only, so it does not cut the header band
            Rectangle {
                x: root.weekColumn + 2
                y: 18 + monthGrid.spacing
                width: 1; height: monthGrid.implicitHeight - 18 - monthGrid.spacing
                color: root.shell.alpha(root.shell.foreground, .1)
            }

        Grid {
            id: monthGrid
            width: parent.width; columns: 8; spacing: 2

            Rectangle {
                width: root.weekColumn; height: Style.px(18); radius: root.shell.rounding
                color: weekStartMouse.containsMouse ? root.shell.hoverFill(1.5) : "transparent"
                Text {
                    anchors.centerIn: parent; text: "W"
                    color: weekStartMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : Qt.darker(root.shell.foreground, 1.9)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    font.bold: true; font.letterSpacing: 1
                }
                MouseArea {
                    id: weekStartMouse; anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                }
            }
            Repeater {
                model: root.weekdays
                Text {
                    required property var modelData
                    width: root.cellWidth; height: Style.px(18); text: modelData
                    color: root.shell.alpha(root.shell.foreground, .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Repeater {
                model: 48
                Rectangle {
                    id: dayCell
                    required property int index
                    readonly property int column: index % 8
                    readonly property bool isWeek: column === 0
                    readonly property date day: root.dateAt(Math.floor(index / 8) * 7 + Math.max(0, column - 1))
                    readonly property bool current: !isWeek && root.sameDay(day, root.today)
                    readonly property bool focused: !isWeek && root.sameDay(day, root.cursor)

                    readonly property bool hovered: !isWeek && dayArea.containsMouse
                    readonly property bool weekHovered: isWeek && dayArea.containsMouse

                    width: isWeek ? root.weekColumn : root.cellWidth
                    height: Style.px(31); radius: root.shell.rounding
                    // the foreground reads against this background; hvr_bg does not
                    color: current ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .35)
                        : hovered ? root.shell.alpha(root.shell.foreground, .12) : "transparent"
                    border.color: current ? root.shell.alpha(root.shell.role("act_br", root.shell.accent), .7)
                        : focused ? root.shell.alpha(root.shell.foreground, .45)
                        : hovered ? root.shell.alpha(root.shell.foreground, .2) : "transparent"
                    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (dayCell.isWeek) {
                                root.cursor = dayCell.day
                                root.agendaMode = "week"
                                root.expanded = true
                                return
                            }
                            const already = root.agendaMode === "day"
                                && root.sameDay(dayCell.day, root.cursor)
                            root.cursor = dayCell.day
                            root.agendaMode = "day"
                            if (dayCell.day.getMonth() !== root.viewDate.getMonth())
                                root.viewDate = new Date(dayCell.day.getFullYear(), dayCell.day.getMonth(), 1)
                            root.expanded = already ? !root.expanded : true
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        spacing: 3
                        Repeater {
                            model: dayCell.isWeek ? [] : root.timedCalendars(dayCell.day)
                            Rectangle {
                                required property var modelData
                                width: Style.px(4); height: Style.px(4); radius: 2
                                color: root.shell.alpha(root.calendarColor(String(modelData),
                                    root.shell.role("act_br", root.shell.accent)), .9)
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: dayCell.isWeek ? root.isoWeek(dayCell.day) : dayCell.day.getDate()
                        color: dayCell.isWeek
                            ? (dayCell.weekHovered
                                ? root.shell.role("hvr_fg", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .3))
                            : dayCell.day.getMonth() !== root.viewDate.getMonth() ? root.shell.alpha(root.shell.foreground, .25)
                            : root.dayTint(dayCell.day)
                        font.family: root.shell.fontFamily
                        font.pixelSize: dayCell.isWeek ? Style.caption : Style.body
                        font.bold: dayCell.current
                    }
                }
            }
        }
        }
        Item {
            width: parent.width; height: Style.px(24)
            NavButton { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; glyph: "«"; onActivated: root.moveYear(-1) }
            NavButton { anchors.left: parent.left; anchors.leftMargin: Style.px(26); anchors.verticalCenter: parent.verticalCenter; glyph: "‹"; onActivated: root.moveMonth(-1) }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: root.shell.alpha(root.shell.foreground, .7)
                font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true; font.letterSpacing: 1
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.goToToday() }
            }
            NavButton { anchors.right: parent.right; anchors.rightMargin: Style.px(26); anchors.verticalCenter: parent.verticalCenter; glyph: "›"; onActivated: root.moveMonth(1) }
            NavButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "»"; onActivated: root.moveYear(1) }
        }

        WheelHandler { onWheel: event => { if (event.angleDelta.y) root.moveMonth(event.angleDelta.y > 0 ? -1 : 1) } }
        }

        Item {
            id: agendaPane
            width: root.expanded ? root.agendaWidth : 0
            height: agendaContent.implicitHeight
            visible: root.expanded
            clip: true

            Column {
            id: agendaContent
            anchors.right: parent.right
            width: root.agendaWidth
            spacing: Style.px(10)

        Item {
            width: parent.width
            height: Math.max(agendaTitle.implicitHeight, modePills.implicitHeight)
            Text {
                id: agendaTitle
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - modePills.width - Style.sm
                elide: Text.ElideRight
                readonly property string dayLabel: Qt.formatDate(root.cursor, "dddd d MMMM").toUpperCase()
                text: root.editingUid !== "" ? "EDITING \u2014 " + dayLabel
                    : root.detailing ? String(root.detailValues.calendar || "").toUpperCase() + " \u2014 " + dayLabel
                    : root.agendaMode === "week" ? root.weekHeading.toUpperCase()
                    : dayLabel
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                font.letterSpacing: 1; font.bold: true
            }
            Row {
                id: modePills
                visible: !root.showingCard
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: Style.xs
                Repeater {
                    model: ["day", "week"]
                    Chip {
                        required property var modelData
                        text: String(modelData).toUpperCase()
                        selected: root.agendaMode === String(modelData)
                        onPicked: root.agendaMode = String(modelData)
                    }
                }
            }
        }
        Text {
            visible: root.agendaMode === "day" && root.agendaEvents.length === 0 && !root.showingCard
            width: parent.width
            text: root.agenda.unavailable === true ? "khal is not configured" : "Nothing scheduled"
            color: root.shell.alpha(root.shell.foreground, .35)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        Column {
            visible: root.agendaMode === "day" && !root.showingCard
            width: parent.width; spacing: 3
            Repeater {
                model: root.agendaEvents
                Item {
                    id: eventItem
                    required property var modelData
                    width: parent.width
                    height: eventRow.implicitHeight

                    HoverHandler { id: eventHover }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: root.shell.rounding
                        color: eventHover.hovered
                            ? root.shell.alpha(root.shell.foreground, .08) : "transparent"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openEvent(eventItem.modelData)
                    }

                    Row {
                    id: eventRow
                    width: parent.width; spacing: Style.sm
                    Text {
                        width: Style.px(40)
                        text: eventItem.modelData.allDay ? "all" : eventItem.modelData.start
                        color: root.eventColor(eventItem.modelData)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                    Column {
                        width: parent.width - 40 - Style.sm - 22; spacing: 0
                        Text {
                            width: parent.width; text: eventItem.modelData.title; elide: Text.ElideRight
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Row {
                            width: parent.width; spacing: Style.xs
                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: [root.foreignCalendar(eventItem.modelData),
                                    eventItem.modelData.location,
                                    eventItem.modelData.description].filter(part => !!part).join("  ·  ")
                                elide: Text.ElideRight
                                color: root.shell.alpha(root.shell.foreground, .4)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            }
                        }
                    }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: eventHover.hovered && !root.isReadonly(eventItem.modelData)
                        width: Style.px(20); height: Style.px(20); radius: root.shell.rounding
                        color: binArea.containsMouse
                            ? root.shell.alpha(root.shell.role("error", root.shell.foreground), .25) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0a7a}"
                            color: binArea.containsMouse ? root.shell.role("error", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .6)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        MouseArea {
                            id: binArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.deleteEvent(eventItem.modelData.uid)
                        }
                    }
                }
            }
        }

        Column {
            visible: root.agendaMode === "week" && !root.showingCard
            width: parent.width; spacing: Style.xs

            Item {
                width: parent.width; height: Style.px(22)
                NavButton {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u2039"; size: Style.display; onActivated: root.moveDay(-7)
                }
                NavButton {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u203a"; size: Style.display; onActivated: root.moveDay(7)
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.weekKeys.indexOf(root.isoDay(root.today)) < 0
                    text: "\u{f0954}  this week"
                    color: root.shell.alpha(root.shell.foreground, mouse.containsMouse ? .9 : .45)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    MouseArea {
                        id: mouse
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.goToToday()
                    }
                }
            }

            Repeater {
                model: root.weekKeys
                Rectangle {
                    id: dayCard
                    required property string modelData
                    readonly property var events: root.eventsOn(dayCard.modelData)
                    readonly property date date: root.dateFromIso(dayCard.modelData)
                    readonly property bool isToday: dayCard.modelData === root.isoDay(root.today)
                    readonly property bool isSelected: dayCard.modelData === root.isoDay(root.cursor)
                    readonly property bool isWeekend: root.isWeekendIso(dayCard.modelData)

                    width: parent.width
                    height: cardRow.implicitHeight + Style.px(14)
                    radius: root.shell.rounding
                    color: dayCard.isSelected
                        ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .3)
                        : dayCard.isToday ? root.shell.alpha(root.shell.foreground, .07)
                        : dayCard.isWeekend ? root.shell.alpha(root.shell.foreground, .025)
                        : root.shell.alpha(root.shell.foreground, .04)
                    border.width: dayCard.isToday && !dayCard.isSelected ? 1 : 0
                    border.color: root.shell.alpha(root.shell.foreground, .2)

                    Rectangle {
                        visible: dayCard.isToday || dayCard.isSelected
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: Style.px(3); height: parent.height - Style.px(10); radius: 1
                        color: root.shell.role("act_br", root.shell.accent)
                    }

                    MouseArea {
                        z: -1
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.cursor = dayCard.date
                    }

                    Row {
                        id: cardRow
                        x: Style.px(8); y: Style.px(7)
                        width: parent.width - Style.px(16); spacing: Style.sm

                        Column {
                            id: dateRail
                            width: Style.px(58); spacing: 0
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: Qt.formatDate(dayCard.date, "ddd").toUpperCase()
                                color: root.shell.alpha(root.shell.foreground, dayCard.isWeekend ? .35 : .5)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                font.letterSpacing: 1; font.bold: dayCard.isToday
                            }
                            Text {
                                text: dayCard.date.getDate() + " · " + Qt.formatDate(dayCard.date, "MMM")
                                color: root.shell.foreground
                                font.family: root.shell.fontFamily; font.pixelSize: Style.body
                                font.bold: dayCard.isToday || dayCard.isSelected
                            }
                            Text {
                                visible: text !== ""
                                text: root.relativeDayLabel(dayCard.modelData)
                                color: dayCard.isToday
                                    ? root.shell.role("act_br", root.shell.accent)
                                    : root.shell.alpha(root.shell.foreground, .35)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                font.italic: true
                            }
                        }

                        Rectangle {
                            width: 1; height: cardRow.implicitHeight
                            color: root.shell.alpha(root.shell.foreground, .1)
                        }

                        Column {
                            id: chipColumn
                            width: cardRow.width - dateRail.width - 1 - cardRow.spacing * 2
                            spacing: Style.xs
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                model: dayCard.events.slice(0, 3)
                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    readonly property color tint: root.chipColor(chip.modelData)
                                    width: chipColumn.width; height: Style.px(22)
                                    radius: root.shell.rounding
                                    color: root.shell.alpha(chip.tint, .13)
                                    border.width: 1
                                    border.color: root.shell.alpha(chip.tint, .24)
                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: Style.controlPaddingX
                                        anchors.rightMargin: Style.controlPaddingX
                                        spacing: Style.xs
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 2; height: Style.px(12); radius: 1; color: chip.tint
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Style.px(38)
                                            text: chip.modelData.allDay ? "all" : chip.modelData.start
                                            color: root.shell.alpha(root.shell.foreground, .55)
                                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - Style.px(38) - 2 - Style.xs * 2
                                            text: chip.modelData.title; elide: Text.ElideRight
                                            color: root.shell.foreground
                                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.cursor = dayCard.date
                                            root.openEvent(chip.modelData)
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: dayCard.events.length > 3
                                width: chipColumn.width
                                text: "+" + (dayCard.events.length - 3) + " more"
                                color: root.shell.alpha(root.shell.foreground, .4)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                font.italic: true
                            }
                            Text {
                                visible: dayCard.events.length === 0
                                width: chipColumn.width
                                text: "— Free —"
                                color: root.shell.alpha(root.shell.foreground, .28)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                font.italic: true
                            }
                        }
                    }
                }
            }
        }

        Loader {
            width: parent.width
            active: root.detailing
            visible: active
            sourceComponent: Component {
                Rectangle {
                    width: parent ? parent.width : 0
                    implicitHeight: Math.max(detailColumn.implicitHeight + Style.controlPaddingX * 2,
                        calendar.implicitHeight - agendaTitle.implicitHeight - agendaContent.spacing)
                    radius: root.shell.rounding
                    color: "transparent"
                    border.width: 1
                    border.color: root.shell.alpha(root.shell.foreground, .2)
                    focus: true
                    Keys.onEscapePressed: root.closeDetail()

                    Column {
                        id: detailColumn
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top; anchors.margins: Style.controlPaddingX
                        spacing: Style.sm

                        Text {
                            width: parent.width; wrapMode: Text.Wrap
                            text: String(root.detailValues.title || "")
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.display
                            font.bold: true
                        }
                        Row {
                            spacing: Style.sm
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Style.px(6); height: Style.px(6); radius: 3
                                color: root.calendarColor(String(root.detailValues.calendar || ""),
                                    root.shell.role("act_br", root.shell.accent))
                            }
                            Text {
                                text: String(root.detailValues.calendar || "") + "  ·  read-only"
                                color: root.shell.alpha(root.shell.foreground, .45)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            }
                        }

                        Item { width: 1; height: Style.xs }

                        FieldLabel { text: "WHEN" }
                        Text {
                            width: parent.width; text: root.detailWhen()
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }

                        FieldLabel { visible: repeatValue.visible; text: "REPEATS" }
                        Text {
                            id: repeatValue
                            visible: text !== ""
                            width: parent.width; text: String(root.detailValues.repeat || "")
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }

                        FieldLabel { visible: locationValue.visible; text: "WHERE" }
                        Text {
                            id: locationValue
                            visible: text !== ""
                            width: parent.width; wrapMode: Text.Wrap
                            text: String(root.detailValues.location || "")
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }

                        FieldLabel { visible: notesValue.visible; text: "NOTES" }
                        Text {
                            id: notesValue
                            visible: text !== ""
                            width: parent.width; wrapMode: Text.Wrap
                            text: String(root.detailValues.description || "")
                            color: root.shell.alpha(root.shell.foreground, .75)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                    }

                    FormButton {
                        anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.margins: Style.controlPaddingX
                        width: root.choiceColumn; text: "Close"
                        onActivated: root.closeDetail()
                    }
                    Component.onCompleted: forceActiveFocus()
                }
            }
        }

        Loader {
            width: parent.width
            active: root.composing
            visible: active
            sourceComponent: Component {
                Rectangle {
                    width: parent ? parent.width : 0
                    implicitHeight: Math.max(formColumn.implicitHeight + Style.controlPaddingX * 2,
                        calendar.implicitHeight - agendaTitle.implicitHeight - agendaContent.spacing)
                    radius: root.shell.rounding
                    color: "transparent"
                    border.width: 1
                    border.color: root.shell.alpha(root.shell.foreground, .2)

                    Column {
                        id: formColumn
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top; anchors.margins: Style.controlPaddingX
                        spacing: Style.sm

                        FormField {
                            id: titleField
                            width: parent.width; text: root.editingValues.title || ""
                            placeholderText: "What is happening"
                            Keys.onReturnPressed: startField.forceActiveFocus()
                            Keys.onEnterPressed: startField.forceActiveFocus()
                        }

                        Item { width: 1; height: Style.xs }

                        Item {
                            width: parent.width; height: Math.max(allDayLabel.implicitHeight, allDaySwitch.height)
                            FieldLabel { id: allDayLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "ALL DAY" }
                            ToggleSwitch { id: allDaySwitch; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; shell: root.shell; checked: root.composeAllDay; onToggled: root.composeAllDay = !root.composeAllDay }
                        }

                        Item { width: 1; height: Style.xs }

                        Row {
                            width: parent.width; spacing: Style.lg
                            Column { id: startFields; width: root.choiceColumn - Style.controlPaddingX * 2; spacing: Style.sm
                                opacity: root.composeAllDay ? .35 : 1
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                FieldLabel { text: "START" }
                                FormField {
                                    id: startField; width: parent.width; enabled: !root.composeAllDay
                                    text: root.editingValues.start || ""; placeholderText: "09:00"; inputMask: "99:99"
                                    Keys.onReturnPressed: endField.forceActiveFocus(); Keys.onEnterPressed: endField.forceActiveFocus()
                                }
                            }
                            Item { width: Style.xl; height: startFields.implicitHeight; opacity: startFields.opacity
                                Text { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Style.px(24)
                                    text: "→"; color: root.shell.alpha(root.shell.foreground, .35)
                                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Column { id: endFields; width: startFields.width; spacing: Style.sm; opacity: startFields.opacity
                                FieldLabel { text: "END" }
                                FormField {
                                    id: endField; width: parent.width; enabled: !root.composeAllDay
                                    text: root.editingValues.end || ""; placeholderText: "optional"; inputMask: "99:99"
                                    Keys.onReturnPressed: endDayField.forceActiveFocus(); Keys.onEnterPressed: endDayField.forceActiveFocus()
                                }
                            }
                            Item { width: parent.width - startFields.width * 2 - untilFields.width - Style.xl - parent.spacing * 4; height: 1 }
                            Column { id: untilFields; width: root.choiceColumn + Style.controlPaddingX * 2; spacing: Style.sm
                                FieldLabel { text: "UNTIL" }
                                FormField {
                                    id: endDayField; width: parent.width
                                    text: root.editingValues.endDay || ""; placeholderText: root.isoDay(root.cursor); inputMask: "9999-99-99"
                                    Keys.onReturnPressed: locationField.forceActiveFocus(); Keys.onEnterPressed: locationField.forceActiveFocus()
                                }
                            }
                        }

                        Item { width: 1; height: Style.xs }

                        FormField {
                            id: locationField; width: parent.width; z: 10
                            text: root.editingValues.location || ""; placeholderText: "Location (optional)"

                            readonly property bool listOpen: activeFocus && !root.locationDismissed
                                && root.locationSuggestions.length > 0
                            function accept(value) {
                                locationField.text = String(value)
                                locationField.cursorPosition = locationField.text.length
                            }
                            onTextChanged: if (locationField.activeFocus) root.locationQuery = text
                            onActiveFocusChanged: if (!activeFocus) root.locationDismissed = true

                            Keys.onReturnPressed: event => {
                                if (locationField.listOpen) {
                                    locationField.accept(root.locationSuggestions[root.locationIndex])
                                    event.accepted = true
                                    return
                                }
                                descriptionField.forceActiveFocus()
                            }
                            Keys.onEnterPressed: event => {
                                if (locationField.listOpen) {
                                    locationField.accept(root.locationSuggestions[root.locationIndex])
                                    event.accepted = true
                                    return
                                }
                                descriptionField.forceActiveFocus()
                            }
                            Keys.onTabPressed: event => {
                                if (!locationField.listOpen) {
                                    event.accepted = false
                                    return
                                }
                                locationField.accept(root.locationSuggestions[root.locationIndex])
                                event.accepted = true
                            }
                            Keys.onDownPressed: event => {
                                if (!locationField.listOpen) {
                                    event.accepted = false
                                    return
                                }
                                root.locationIndex = Math.min(root.locationIndex + 1,
                                    root.locationSuggestions.length - 1)
                                event.accepted = true
                            }
                            Keys.onUpPressed: event => {
                                if (!locationField.listOpen) {
                                    event.accepted = false
                                    return
                                }
                                root.locationIndex = Math.max(root.locationIndex - 1, 0)
                                event.accepted = true
                            }
                            Keys.onEscapePressed: event => {
                                if (locationField.listOpen) {
                                    root.locationDismissed = true
                                    event.accepted = true
                                    return
                                }
                                root.cancelCompose()
                            }

                            Rectangle {
                                visible: locationField.listOpen
                                y: locationField.height + 2
                                width: locationField.width
                                height: suggestionColumn.implicitHeight + 2
                                radius: root.shell.rounding
                                color: root.shell.role("bg", root.shell.background)
                                border.width: 1
                                border.color: root.shell.alpha(root.shell.foreground, .25)
                                Column {
                                    id: suggestionColumn
                                    y: 1; width: parent.width
                                    Repeater {
                                        model: root.locationSuggestions
                                        Rectangle {
                                            id: suggestionRow
                                            required property var modelData
                                            required property int index
                                            width: suggestionColumn.width; height: Style.px(20)
                                            color: suggestionRow.index === root.locationIndex
                                                ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .35)
                                                : hoverArea.containsMouse
                                                ? root.shell.alpha(root.shell.foreground, .08) : "transparent"
                                            Text {
                                                anchors.fill: parent
                                                anchors.leftMargin: Style.controlPaddingX
                                                anchors.rightMargin: Style.controlPaddingX
                                                verticalAlignment: Text.AlignVCenter
                                                text: String(suggestionRow.modelData); elide: Text.ElideRight
                                                color: root.shell.foreground
                                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                                            }
                                            MouseArea {
                                                id: hoverArea
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: locationField.accept(suggestionRow.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        FormArea {
                            id: descriptionField; width: parent.width; lines: 2
                            text: root.editingValues.description || ""; placeholderText: "Description (optional)"
                        }

                        Item { width: 1; height: Style.xs }

                        Row {
                            id: calendarRow
                            visible: root.writableCalendars.length > 1
                            width: parent.width; height: Style.px(22); spacing: Style.sm
                            FieldLabel {
                                id: calendarLabel
                                width: root.choiceColumn - Style.controlPaddingX * 2
                                height: parent.height; text: "CALENDAR"
                                verticalAlignment: Text.AlignVCenter
                            }
                            Repeater {
                                model: root.writableCalendars
                                Chip {
                                    required property var modelData
                                    width: (calendarRow.width - calendarLabel.width
                                        - calendarRow.spacing * root.writableCalendars.length)
                                        / root.writableCalendars.length
                                    text: String(modelData)
                                    selected: root.composeCalendar === String(modelData)
                                    onPicked: root.composeCalendar = String(modelData)
                                }
                            }
                        }
                        Row {
                            id: alarmRow
                            width: parent.width; height: Style.px(22); spacing: Style.sm
                            FieldLabel { id: alertLabel; width: root.choiceColumn - Style.controlPaddingX * 2; height: parent.height; text: "ALERT"; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: root.alarmChoices
                                Chip {
                                    required property var modelData
                                    width: (alarmRow.width - alertLabel.width - alarmRow.spacing * root.alarmChoices.length) / root.alarmChoices.length
                                    text: modelData.label; selected: root.composeAlarm === modelData.value
                                    onPicked: root.composeAlarm = modelData.value
                                }
                            }
                        }
                        Row {
                            id: repeatRow
                            width: parent.width; height: Style.px(22); spacing: Style.sm
                            FieldLabel { id: repeatLabel; width: alertLabel.width; height: parent.height; text: "REPEAT"; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: root.repeatChoices
                                Chip {
                                    required property var modelData
                                    width: (repeatRow.width - repeatLabel.width - repeatRow.spacing * root.repeatChoices.length) / root.repeatChoices.length
                                    text: modelData.label; selected: root.composeRepeat === modelData.value
                                    onPicked: root.composeRepeat = modelData.value
                                }
                            }
                        }

                        Item { width: 1; height: Style.xs }

                        Item {
                            width: parent.width; height: Style.px(24)
                            Text {
                                visible: root.composeError !== ""
                                anchors.left: parent.left; anchors.right: formButtons.left; anchors.rightMargin: Style.sm
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f002a}  " + root.composeError; elide: Text.ElideRight
                                color: root.shell.role("error", root.shell.foreground)
                                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            }
                            Row {
                                id: formButtons; anchors.right: parent.right; spacing: Style.lg
                                FormButton { width: root.choiceColumn; text: "Cancel"; onActivated: root.cancelCompose() }
                                FormButton {
                                    width: root.choiceColumn; text: root.editingUid !== "" ? "Save" : "Add"; primary: true
                                    onActivated: root.saveRequested()
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: "↑↓ Tab  suggestions     Ctrl+Enter  save     Esc  cancel"
                            color: root.shell.alpha(root.shell.foreground, .3)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Connections {
                        target: root
                        function onSaveRequested() {
                            root.saveEvent({
                                title: titleField.text, start: startField.text,
                                end: endField.text, endDay: endDayField.text,
                                location: locationField.text, description: descriptionField.text
                            })
                        }
                    }
                    Component.onCompleted: titleField.forceActiveFocus()
                }
            }
        }

        Rectangle {
            width: parent.width; height: Style.px(26)
            visible: root.agendaMode === "day" && !root.showingCard
            radius: root.shell.rounding
            color: addArea.containsMouse ? root.shell.alpha(root.shell.foreground, .1) : "transparent"
            border.width: addArea.containsMouse ? 1 : 0
            border.color: root.shell.alpha(root.shell.foreground, .25)
            Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: "\u{f0415}  Add event"
                color: root.shell.alpha(root.shell.foreground, addArea.containsMouse ? .9 : .45)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            MouseArea {
                id: addArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.startCompose()
            }
        }
    }

            }
        }

}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "CalendarMath.js" as CalendarMath

PopupCard {
    id: root
    popupName: "clock"
    readonly property int calendarWidth: Style.px(440) - padding * 2
    readonly property int agendaWidth: Style.px(520)
    readonly property int choiceColumn: Style.px(84)
    readonly property int paneGap: Style.px(16)
    property bool agendaVisible: false
    contentWidth: calendarWidth + padding * 2 + (agendaVisible ? agendaWidth + paneGap : 0)
    contentHeight: Math.max(calendar.implicitHeight, agendaVisible ? agendaPane.height : 0) + Style.px(32)

    readonly property date today: root.shell.clock.date
    property date visibleMonth: new Date(today.getFullYear(), today.getMonth(), 1)

    // Locale.Sunday === 0. The locale decides unless overridden; en_US says
    // Sunday, which is not what everyone wants.
    property int weekStartOverride: -1
    readonly property int weekStart: weekStartOverride >= 0 ? weekStartOverride : Qt.locale().firstDayOfWeek
    readonly property string otherWeekStartName: Qt.locale().dayName(weekStart === 1 ? 0 : 1, Locale.LongFormat)

    property date selectedDate: today
    readonly property var weekdayLabels: {
        const names = []
        for (let day = 0; day < 7; day++)
            names.push(Qt.locale().dayName((weekStart + day) % 7, Locale.ShortFormat).toUpperCase())
        return names
    }
    readonly property int leadingBlankDays: {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1).getDay()
        return (first - weekStart + 7) % 7
    }

    readonly property int weekNumberColumnWidth: 26
    readonly property real dayCellWidth: (calendar.width - weekNumberColumnWidth - 14) / 7

    function moveMonth(delta) { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1) }
    function moveYear(delta) { visibleMonth = new Date(visibleMonth.getFullYear() + delta, visibleMonth.getMonth(), 1) }
    function goToToday() {
        selectedDate = today
        visibleMonth = new Date(today.getFullYear(), today.getMonth(), 1)
    }
    function moveDay(days) {
        const next = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + days)
        selectedDate = next
        if (next.getFullYear() !== visibleMonth.getFullYear() || next.getMonth() !== visibleMonth.getMonth())
            visibleMonth = new Date(next.getFullYear(), next.getMonth(), 1)
    }
    property var settingsSnapshot: ({})
    property bool settingsLoaded: false
    function persist() {
        if (!settingsLoaded) return
        const saved = settingsSnapshot || ({})
        saved.weekStart = weekStartOverride
        saved.agendaMode = agendaMode
        settingsSnapshot = saved
        settingsFile.setText(JSON.stringify(saved))
    }
    function toggleWeekStart() {
        weekStartOverride = weekStart === 1 ? 0 : 1
        persist()
    }
    function dateAt(index) { return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), index - leadingBlankDays + 1) }

    property var selectedDayAgenda: ({})
    property var monthMarkersByDate: ({})
    property var weekEventsByDate: ({})
    property string agendaMode: "day"
    readonly property string selectedWeekStart: CalendarMath.isoDay(CalendarMath.startOfWeek(selectedDate, weekStart))
    readonly property var selectedWeekDates: {
        const start = CalendarMath.startOfWeek(selectedDate, weekStart)
        const keys = []
        for (let offset = 0; offset < 7; offset++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + offset)
            keys.push(CalendarMath.isoDay(day))
        }
        return keys
    }
    readonly property string weekHeading: {
        const keys = selectedWeekDates
        if (keys.length !== 7) return ""
        const first = CalendarMath.fromIsoDay(keys[0])
        const last = CalendarMath.fromIsoDay(keys[6])
        return "W" + CalendarMath.isoWeek(first) + "  ·  " + Qt.formatDate(first, "MMM d")
            + " – " + Qt.formatDate(last, "MMM d, yyyy")
    }
    function eventsOnDate(iso) { return weekEventsByDate[String(iso)] || [] }
    function relativeDayLabel(iso) {
        return CalendarMath.relativeDayLabel(iso, root.today)
    }
    function eventChipColor(event) {
        return calendarColor(String(event.calendar || ""),
            root.shell.role("act_br", root.shell.accent))
    }
    readonly property var selectedDayEvents: selectedDayAgenda.events || []

    property var calendars: ({})
    property string defaultCalendar: ""
    property var locations: []
    property var locationSearchResults: []
    property string locationQuery: ""
    property int locationSelectionIndex: 0
    property bool locationSuggestionsDismissed: false
    onLocationQueryChanged: {
        locationSelectionIndex = 0
        locationSuggestionsDismissed = false
        locationSearchDebounce.restart()
    }
    readonly property var locationSuggestions: {
        const typed = String(locationQuery)
        const prefix = typed.toLowerCase()
        const mine = prefix === ""
            ? [] : locations.filter(known => String(known).toLowerCase().startsWith(prefix))
        const out = []
        const seen = ({})
        for (const candidate of mine.concat(locationSearchResults)) {
            const value = String(candidate)
            const key = value.toLowerCase()
            if (value === "" || value === typed || seen[key] === true) continue
            seen[key] = true
            out.push(value)
        }
        return out.slice(0, 6)
    }
    property Timer locationSearchDebounce: Timer {
        interval: 350
        onTriggered: {
            if (root.locationQuery.length < 3) {
                root.locationSearchResults = []
                return
            }
            root.locationSearchProcess.running = false
            root.locationSearchProcess.command = ["hyprshell", "calendar/places", root.locationQuery]
            root.locationSearchProcess.running = true
        }
    }
    property Process locationSearchProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.locationSearchResults = JSON.parse(text) || [] } catch (error) { root.locationSearchResults = [] }
        } }
    }
    function clearLocationSearch() {
        locationSearchDebounce.stop()
        locationSearchProcess.running = false
        locationSearchResults = []
        locationQuery = ""
        locationSelectionIndex = 0
        locationSuggestionsDismissed = false
    }
    function calendarMetadata(event) { return calendars[String(event.calendar || "")] || ({}) }
    function eventIsReadOnly(event) { return calendarMetadata(event).readonly === true }
    function secondaryCalendarName(event) {
        const name = String(event.calendar || "")
        return name === defaultCalendar ? "" : name
    }
    readonly property var khalNamedColorIndexes: ({
        "black": 0, "dark red": 1, "dark green": 2, "brown": 3,
        "dark blue": 4, "dark magenta": 5, "dark cyan": 6, "white": 7,
        "dark gray": 8, "light red": 9, "light green": 10, "yellow": 11,
        "light blue": 12, "light magenta": 13, "light cyan": 14, "light gray": 15
    })
    function configuredCalendarColor(name) {
        const declared = String((calendars[String(name)] || {}).color || "").trim().toLowerCase()
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/.test(declared)) return declared
        const named = khalNamedColorIndexes[declared]
        if (named !== undefined) return root.shell.role("c" + named, root.shell.accent)
        if (/^\d{1,3}$/.test(declared) && Number(declared) < 16)
            return root.shell.role("c" + Number(declared), root.shell.accent)
        return ""
    }
    readonly property var fallbackCalendarRoles: ["c1", "c2", "c3", "c4", "c5", "c6"]
    function calendarColor(name, fallback) {
        const declared = configuredCalendarColor(name)
        if (declared !== "") return declared
        if (name === "" || name === defaultCalendar) return fallback
        let hash = 0
        for (let index = 0; index < name.length; index++)
            hash = (hash * 31 + name.charCodeAt(index)) >>> 0
        return root.shell.role(fallbackCalendarRoles[hash % fallbackCalendarRoles.length], root.shell.accent)
    }
    function eventColor(event) {
        return calendarColor(String(event.calendar || ""),
            root.shell.alpha(root.shell.foreground, .55))
    }

    function monthEntryForDate(date) { return monthMarkersByDate[CalendarMath.isoDay(date)] || ({}) }
    function timedCalendarsOnDate(date) { return monthEntryForDate(date).timed || [] }
    function dayNumberColor(date) {
        const marks = monthEntryForDate(date).allDay || []
        return marks.length === 0 ? root.shell.foreground
            : calendarColor(String(marks[0]), root.shell.role("act_br", root.shell.accent))
    }

    function loadSelectedDay() {
        if (!open) return
        selectedDayProcess.running = false
        selectedDayProcess.command = ["hyprshell", "calendar/agenda", "--day", CalendarMath.isoDay(selectedDate)]
        selectedDayProcess.running = true
    }
    function loadVisibleMonth() {
        if (!open) return
        visibleMonthProcess.running = false
        visibleMonthProcess.command = ["hyprshell", "calendar/agenda", "--month", Qt.formatDate(visibleMonth, "yyyy-MM")]
        visibleMonthProcess.running = true
    }
    function loadSelectedWeek() {
        if (!open || agendaMode !== "week") return
        selectedWeekProcess.running = false
        selectedWeekProcess.command = ["hyprshell", "calendar/agenda", "--week", selectedWeekStart]
        selectedWeekProcess.running = true
    }
    onSelectedWeekStartChanged: loadSelectedWeek()
    onAgendaModeChanged: {
        if (agendaMode === "week") agendaVisible = true
        loadSelectedWeek()
        persist()
    }
    property bool eventEditorOpen: false
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
    property bool draftAllDay: false
    property string draftAlarm: ""
    property string draftRepeat: ""
    property string draftCalendar: ""
    readonly property var writableCalendars: {
        const out = []
        for (const name in calendars)
            if (calendars[name].readonly !== true) out.push(name)
        out.sort()
        return out
    }
    signal saveRequested()
    property string editedEventUid: ""
    property var draftValues: ({})
    // khal writes alarms as an ISO duration; map back to the chip values
    function alarmValueForTrigger(trigger) {
        const map = { "-PT0S": "0m", "PT0S": "0m", "-PT10M": "10m", "-PT1H": "1h", "-P1D": "1d" }
        return map[String(trigger)] || ""
    }
    function openEvent(event) {
        const uid = String(event.uid || "")
        if (!uid) return
        eventDetailsProcess.running = false
        eventDetailsProcess.command = ["hyprshell", "calendar/agenda", "--show", uid]
        root.requestedEventUid = uid
        root.requestedEventCalendar = String(event.calendar || "")
        root.requestedEventReadOnly = root.eventIsReadOnly(event)
        eventDetailsProcess.running = true
    }
    property string requestedEventUid: ""
    property string requestedEventCalendar: ""
    property bool requestedEventReadOnly: false
    property Process eventDetailsProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            if (payload.error) { root.eventEditorError = String(payload.error); return }
            const lastDay = CalendarMath.rawDate(payload.endRaw)
            // an all-day DTEND is exclusive, so step it back for display
            const endDay = payload.allDay === true ? CalendarMath.previousDay(lastDay) : lastDay
            const values = {
                title: String(payload.title || ""),
                start: CalendarMath.rawTime(payload.startRaw),
                end: CalendarMath.rawTime(payload.endRaw),
                endDay: endDay,
                location: String(payload.location || ""),
                description: String(payload.description || "")
            }
            if (root.requestedEventReadOnly) {
                values.calendar = root.requestedEventCalendar
                values.allDay = payload.allDay === true
                values.repeat = String(payload.repeat || "")
                values.alarm = root.alarmValueForTrigger(payload.alarm)
                root.eventDetails = values
                root.eventEditorError = ""
                root.eventDetailsOpen = true
                return
            }
            root.editedEventUid = root.requestedEventUid
            root.draftCalendar = root.requestedEventCalendar
            root.draftAllDay = payload.allDay === true
            root.draftRepeat = String(payload.repeat || "")
            root.draftAlarm = root.alarmValueForTrigger(payload.alarm)
            root.draftValues = values
            root.eventEditorError = ""
            root.eventEditorOpen = true
        } }
    }
    function openNewEventEditor() {
        clearLocationSearch()
        eventDetailsOpen = false
        editedEventUid = ""
        draftValues = ({})
        eventEditorError = ""
        draftAllDay = false
        draftAlarm = ""
        draftRepeat = ""
        draftCalendar = defaultCalendar
        eventEditorOpen = true
    }
    function closeEventPanels() {
        clearLocationSearch()
        eventEditorOpen = false; editedEventUid = ""; draftValues = ({}); eventEditorError = ""
        closeEventDetails()
    }
    property bool eventDetailsOpen: false
    property var eventDetails: ({})
    readonly property bool eventPanelOpen: eventEditorOpen || eventDetailsOpen
    function closeEventDetails() { eventDetailsOpen = false; eventDetails = ({}) }
    function eventDetailsTime() {
        if (eventDetails.allDay === true) {
            const last = String(eventDetails.endDay || "")
            return last !== "" && last !== CalendarMath.isoDay(selectedDate) ? "All day, until " + last : "All day"
        }
        const start = String(eventDetails.start || "")
        const end = String(eventDetails.end || "")
        if (start === "") return ""
        return end !== "" ? start + " – " + end : start
    }
    property string eventEditorError: ""
    function validateAndSaveEvent(fields) {
        const title = String(fields.title).trim()
        if (title === "") {
            eventEditorError = "A title is required"
            return
        }
        const timed = /^\d{1,2}:\d{2}$/
        const dated = /^\d{4}-\d{2}-\d{2}$/
        const startText = CalendarMath.enteredValue(fields.start)
        const endText = CalendarMath.enteredValue(fields.end)
        const endDay = CalendarMath.enteredValue(fields.endDay)

        if (endDay !== "" && !dated.test(endDay)) {
            eventEditorError = "Last day must look like 2026-08-18"
            return
        }
        if (endDay !== "" && endDay < CalendarMath.isoDay(selectedDate)) {
            eventEditorError = "Last day is before the first"
            return
        }
        const spansDays = endDay !== "" && endDay !== CalendarMath.isoDay(selectedDate)

        if (!draftAllDay) {
            if (startText === "" && endText === "") {
                eventEditorError = "Set a start time, or switch on All day"
                return
            }
            if (startText === "") {
                eventEditorError = "An end time needs a start time"
                return
            }
            if (!timed.test(startText)) {
                eventEditorError = "Start time must look like 09:00"
                return
            }
            if (endText !== "") {
                if (!timed.test(endText)) {
                    eventEditorError = "End time must look like 10:00"
                    return
                }
                if (!spansDays && endText <= startText) {
                    eventEditorError = "Ends before it starts \u2014 set Last day for overnight"
                    return
                }
            }
        }

        const args = ["--add", "--day", CalendarMath.isoDay(selectedDate), "--title", title]
        if (!draftAllDay) {
            args.push("--start", startText)
            if (endText !== "") args.push("--end", endText)
        }
        if (spansDays) args.push("--end-day", endDay)
        const where = String(fields.location).trim()
        if (where !== "") args.push("--location", where)
        const notes = String(fields.description).trim()
        if (notes !== "") args.push("--description", notes)
        if (draftAlarm !== "") args.push("--alarm", draftAlarm)
        if (draftRepeat !== "") args.push("--repeat", draftRepeat)
        if (draftCalendar !== "") args.push("--calendar", draftCalendar)

        if (editedEventUid !== "") args.push("--delete", editedEventUid)

        eventEditorError = ""
        saveEventProcess.running = false
        saveEventProcess.command = ["hyprshell", "calendar/agenda"].concat(args)
        saveEventProcess.running = true
    }

    function deleteEvent(uid) {
        if (!uid) return
        deleteEventProcess.running = false
        deleteEventProcess.command = ["hyprshell", "calendar/agenda", "--delete", String(uid), "--day", CalendarMath.isoDay(selectedDate)]
        deleteEventProcess.running = true
    }
    property Process deleteEventProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.selectedDayAgenda = JSON.parse(text) || ({}) } catch (error) { root.loadSelectedDay() }
            root.loadVisibleMonth()
        } }
    }

    property Process saveEventProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            if (payload.error) {
                root.eventEditorError = String(payload.error)
                return
            }
            root.eventEditorError = ""
            root.eventEditorOpen = false
            root.editedEventUid = ""
            root.selectedDayAgenda = payload
            root.loadVisibleMonth()
        } }
    }
    property Timer agendaRefreshDelay: Timer { interval: 400; onTriggered: { root.loadSelectedDay(); root.loadVisibleMonth() } }

    onSelectedDateChanged: { closeEventPanels(); loadSelectedDay() }
    onVisibleMonthChanged: loadVisibleMonth()

    property Process selectedDayProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.selectedDayAgenda = JSON.parse(text) || ({}) } catch (error) { root.selectedDayAgenda = ({}) }
        } }
    }
    property Process visibleMonthProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.monthMarkersByDate = (JSON.parse(text) || ({})).days || ({}) } catch (error) { root.monthMarkersByDate = ({}) }
        } }
    }
    property Process selectedWeekProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.weekEventsByDate = (JSON.parse(text) || ({})).days || ({}) } catch (error) { root.weekEventsByDate = ({}) }
        } }
    }
    property Process calendarMetadataProcess: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            root.calendars = payload.calendars || ({})
            root.defaultCalendar = String(payload.default || "")
            root.locations = payload.locations || []
        } }
    }
    function loadCalendars() {
        calendarMetadataProcess.running = false
        calendarMetadataProcess.command = ["hyprshell", "calendar/agenda", "--calendars"]
        calendarMetadataProcess.running = true
    }

    onOpenChanged: {
        if (open) {
            agendaVisible = agendaMode === "week"
            goToToday()
            loadCalendars(); loadSelectedDay(); loadVisibleMonth(); loadSelectedWeek()
        } else closeEventPanels()
    }

    property FileView settingsFile: FileView {
        path: root.shell.home + "/.local/state/quickshell/clock.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text()) || ({})
                root.settingsSnapshot = saved
                root.weekStartOverride = saved.weekStart !== undefined ? saved.weekStart : -1
                root.agendaMode = saved.agendaMode === "week" ? "week" : "day"
            } catch (error) {
                root.settingsSnapshot = ({})
                root.weekStartOverride = -1
            }
            root.settingsLoaded = true
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.paneGap
        layoutDirection: root.position === "right" ? Qt.RightToLeft : Qt.LeftToRight

    Column {
        id: calendar
        width: root.calendarWidth
        spacing: Style.px(14)
        focus: !root.eventPanelOpen

        Keys.onPressed: event => {
            if (root.eventEditorOpen) return
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
                x: root.weekNumberColumnWidth + 2
                y: 18 + monthGrid.spacing
                width: 1; height: monthGrid.implicitHeight - 18 - monthGrid.spacing
                color: root.shell.alpha(root.shell.foreground, .1)
            }

        Grid {
            id: monthGrid
            width: parent.width; columns: 8; spacing: 2

            Rectangle {
                width: root.weekNumberColumnWidth; height: Style.px(18); radius: root.shell.rounding
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
                model: root.weekdayLabels
                Text {
                    required property var modelData
                    width: root.dayCellWidth; height: Style.px(18); text: modelData
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
                    readonly property bool current: !isWeek && CalendarMath.sameDay(day, root.today)
                    readonly property bool focused: !isWeek && CalendarMath.sameDay(day, root.selectedDate)

                    readonly property bool hovered: !isWeek && dayArea.containsMouse
                    readonly property bool weekHovered: isWeek && dayArea.containsMouse

                    width: isWeek ? root.weekNumberColumnWidth : root.dayCellWidth
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
                                root.selectedDate = dayCell.day
                                root.agendaMode = "week"
                                root.agendaVisible = true
                                return
                            }
                            const already = root.agendaMode === "day"
                                && CalendarMath.sameDay(dayCell.day, root.selectedDate)
                            root.selectedDate = dayCell.day
                            root.agendaMode = "day"
                            if (dayCell.day.getMonth() !== root.visibleMonth.getMonth())
                                root.visibleMonth = new Date(dayCell.day.getFullYear(), dayCell.day.getMonth(), 1)
                            root.agendaVisible = already ? !root.agendaVisible : true
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        spacing: 3
                        Repeater {
                            model: dayCell.isWeek ? [] : root.timedCalendarsOnDate(dayCell.day)
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
                        text: dayCell.isWeek ? CalendarMath.isoWeek(dayCell.day) : dayCell.day.getDate()
                        color: dayCell.isWeek
                            ? (dayCell.weekHovered
                                ? root.shell.role("hvr_fg", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .3))
                            : dayCell.day.getMonth() !== root.visibleMonth.getMonth() ? root.shell.alpha(root.shell.foreground, .25)
                            : root.dayNumberColor(dayCell.day)
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
            ClockNavButton { popup: root; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; glyph: "«"; onActivated: root.moveYear(-1) }
            ClockNavButton { popup: root; anchors.left: parent.left; anchors.leftMargin: Style.px(26); anchors.verticalCenter: parent.verticalCenter; glyph: "‹"; onActivated: root.moveMonth(-1) }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(root.visibleMonth, "MMMM yyyy").toUpperCase()
                color: root.shell.alpha(root.shell.foreground, .7)
                font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true; font.letterSpacing: 1
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.goToToday() }
            }
            ClockNavButton { popup: root; anchors.right: parent.right; anchors.rightMargin: Style.px(26); anchors.verticalCenter: parent.verticalCenter; glyph: "›"; onActivated: root.moveMonth(1) }
            ClockNavButton { popup: root; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "»"; onActivated: root.moveYear(1) }
        }

        WheelHandler { onWheel: event => { if (event.angleDelta.y) root.moveMonth(event.angleDelta.y > 0 ? -1 : 1) } }
        }

        ClockAgendaPane { id: agendaPane; popup: root; calendarHeight: calendar.implicitHeight }
        }

}

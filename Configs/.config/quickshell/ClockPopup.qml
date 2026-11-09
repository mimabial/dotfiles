pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "CalendarMath.js" as CalendarMath
import "Units.js" as Units

PopupCard {
    id: root
    readonly property string agendaScript: root.shell.home + "/.local/lib/hypr/calendar/agenda.sh"
    readonly property int minLocationQuery: 3
    popupName: "clock"
    keyboardHint: quickAddFocused ? "Enter Add  Shift+Enter Full form  Esc Back"
        : "Arrows Day  PgUp/PgDn Month  Home Today  W Week  "
        + (agendaVisible ? "J/K Event  Enter Open  N Quick add  E Edit  " : "") + "Esc"
    readonly property int calendarWidth: weekNumberColumnWidth + weekGutterWidth + 7 * (dayCellWidth + monthGrid.spacing)
    readonly property int agendaWidth: Style.px(330)
    readonly property int choiceColumn: Style.px(84)
    readonly property int paneGap: Style.sectionGap
    readonly property int dividerWidth: 1
    property bool agendaVisible: false
    contentWidth: calendarWidth + padding * 2 + (agendaVisible ? agendaWidth + paneGap * 2 + dividerWidth : 0)
    contentHeight: Math.max(calendar.implicitHeight, agendaVisible ? agendaPane.height : 0) + Style.px(32)

    readonly property date today: root.shell.clock.date
    property date visibleMonth: new Date(today.getFullYear(), today.getMonth(), 1)

    property int weekStartOverride: -1
    readonly property int weekStart: weekStartOverride >= 0 ? weekStartOverride : Qt.locale().firstDayOfWeek

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

    readonly property int weekNumberColumnWidth: Style.px(32)
    readonly property int weekGutterWidth: Style.xxxl
    readonly property int dayCellWidth: Style.px(52)
    readonly property int dayCellHeight: Style.px(34)
    readonly property int weekdayHeaderHeight: Style.px(16)
    readonly property color secondaryText: root.shell.alpha(root.shell.foreground, Style.secondaryTextAlpha)
    readonly property color structureLine: root.shell.alpha(root.shell.foreground, Style.fieldBorderAlpha)

    function moveMonth(delta) { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1) }
    function moveYear(delta) { visibleMonth = new Date(visibleMonth.getFullYear() + delta, visibleMonth.getMonth(), 1) }
    function showDay(day) {
        selectedDate = day
        if (day.getFullYear() !== visibleMonth.getFullYear() || day.getMonth() !== visibleMonth.getMonth())
            visibleMonth = new Date(day.getFullYear(), day.getMonth(), 1)
    }
    function goToToday() { showDay(today) }
    function moveDay(days) { showDay(new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + days)) }
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
    readonly property var allDayEvents: selectedDayEvents.filter(event => event.allDay)
    readonly property var timedEvents: selectedDayEvents.filter(event => !event.allDay)
    readonly property var dayItems: allDayEvents.concat(timedEvents)
    readonly property string dayHeading: [Qt.formatDate(selectedDate, "dddd, MMMM d"),
        CalendarMath.relativeDayLabel(CalendarMath.isoDay(selectedDate), today)].filter(part => part !== "").join("  ·  ")
    readonly property string daySummary: [timedEvents.length ? timedEvents.length + (timedEvents.length === 1 ? " event" : " events") : "",
        allDayEvents.length ? allDayEvents.length + " all day" : ""].filter(part => part !== "").join("  ·  ")
    readonly property bool selectedIsToday: CalendarMath.sameDay(selectedDate, today)
    readonly property int nowSeconds: today.getHours() * Units.SECONDS_PER_HOUR + today.getMinutes() * Units.SECONDS_PER_MINUTE
    readonly property int nowLineIndex: {
        if (!selectedIsToday) return -1
        const index = timedEvents.findIndex(event => eventBounds(event).start > nowSeconds)
        return index < 0 ? timedEvents.length : index
    }
    function clockSeconds(clock) {
        const parts = String(clock).split(":")
        return Number(parts[0]) * Units.SECONDS_PER_HOUR + Number(parts[1]) * Units.SECONDS_PER_MINUTE
    }
    function eventBounds(event) {
        const start = clockSeconds(event.start), end = clockSeconds(event.end)
        return { start: start, end: end > start ? end : end + Units.SECONDS_PER_DAY }
    }
    function eventPhase(event) {
        const day = CalendarMath.isoDay(selectedDate), current = CalendarMath.isoDay(today)
        if (day !== current) return day < current ? "past" : "later"
        const bounds = eventBounds(event)
        return nowSeconds >= bounds.end ? "past" : nowSeconds >= bounds.start ? "now" : "later"
    }
    function countdownText(event) {
        const phase = eventPhase(event), bounds = eventBounds(event)
        if (!selectedIsToday || phase === "past") return ""
        return phase === "now" ? "now  ·  " + root.shell.duration(bounds.end - nowSeconds) + " left"
            : "in " + root.shell.duration(bounds.start - nowSeconds)
    }
    function startsSoon(event) {
        const phase = eventPhase(event)
        return selectedIsToday && (phase === "now" || phase === "later"
            && eventBounds(event).start - nowSeconds <= root.shell.upcomingEvents.announceLeadMinutes * Units.SECONDS_PER_MINUTE)
    }
    function openUpcoming(event) {
        showDay(new Date(event.start * Units.MS_PER_SECOND))
        openEvent(event)
    }
    property int selectedEventIndex: -1
    readonly property var selectedEvent: agendaVisible && agendaMode === "day" ? dayItems[selectedEventIndex] || null : null
    onSelectedDayEventsChanged: selectedEventIndex = -1
    function stepEvent(delta) {
        const count = dayItems.length
        if (agendaMode !== "day" || count === 0) return
        agendaVisible = true
        selectedEventIndex = selectedEventIndex < 0 ? (delta > 0 ? 0 : count - 1)
            : Math.max(0, Math.min(count - 1, selectedEventIndex + delta))
    }
    function focusCalendar() { calendar.forceActiveFocus() }

    readonly property string quickAddScript: root.shell.home + "/.local/lib/hypr/calendar/lib/quick_add.py"
    property string quickText: ""
    property bool quickAddFocused: false
    property var quickParse: ({})
    readonly property string quickRequest: CalendarMath.isoDay(selectedDate) + "\t" + quickText.trim()
    readonly property bool quickParseCurrent: quickParse.request === quickRequest
    readonly property bool quickParsed: quickParseCurrent && !quickParse.error
    readonly property string quickError: eventEditorError || (quickParseCurrent && quickParse.error) || ""
    readonly property var quickRows: {
        if (!quickParsed) return []
        const rows = [{ label: "TITLE", value: quickParse.title },
            { label: "STARTS", value: dayName(quickParse.day) + ", " + (quickParse.allDay ? "all day" : quickParse.start) }]
        if (!quickParse.allDay)
            rows.push({ label: "ENDS", value: (quickParse.endDay ? dayName(quickParse.endDay) + ", " : "") + quickParse.end
                + "  ·  " + root.shell.duration(spanSeconds(quickParse.day, quickParse.start, quickParse.endDay || quickParse.day, quickParse.end)) })
        else if (quickParse.endDay) rows.push({ label: "UNTIL", value: dayName(quickParse.endDay) })
        if (quickParse.description) rows.push({ label: "NOTES", value: quickParse.description })
        return rows
    }
    signal quickAddRequested()
    signal eventSaved()
    onQuickRequestChanged: requestQuickParse()
    function dayName(iso) { return CalendarMath.relativeDayLabel(iso, today) || Qt.formatDate(CalendarMath.fromIsoDay(iso), "ddd d MMM") }
    function requestQuickParse() { if (quickText.trim() !== "" && quickParser.running) quickParser.write(quickRequest + "\n") }
    function quickAdd() {
        if (!quickParsed) return
        const args = ["--add", "--day", quickParse.day, "--title", quickParse.title]
        if (!quickParse.allDay) args.push("--start", quickParse.start, "--end", quickParse.end)
        if (quickParse.endDay) args.push("--end-day", quickParse.endDay)
        if (quickParse.description) args.push("--description", quickParse.description)
        saveEvent(args)
    }
    function editQuickAdd() {
        const values = quickParsed ? quickParse : null
        if (values) showDay(CalendarMath.fromIsoDay(values.day))
        openNewEventEditor(values)
    }
    property Process quickParser: Process {
        command: ["python3", root.quickAddScript]
        running: root.open && root.quickAddFocused
        stdinEnabled: true
        onStarted: root.requestQuickParse()
        stdout: SplitParser { onRead: data => {
            try { root.quickParse = JSON.parse(data) } catch (error) { root.quickParse = ({}) }
        } }
    }

    property var calendars: ({})
    property string defaultCalendar: ""
    property var locations: []
    property string locationQuery: ""
    property int locationSelectionIndex: 0
    property bool locationSuggestionsDismissed: false
    readonly property int maxLocationSuggestions: 6
    onLocationQueryChanged: {
        locationSelectionIndex = 0
        locationSuggestionsDismissed = false
        Qt.callLater(root.searchLocations)
    }
    readonly property var locationSuggestions: {
        const typed = String(locationQuery)
        const prefix = typed.toLowerCase()
        const mine = prefix === ""
            ? [] : locations.filter(known => String(known).toLowerCase().startsWith(prefix))
        const out = []
        const seen = ({})
        for (const candidate of mine.concat(addressSearch.results, placeSearch.results)) {
            const value = String(candidate)
            const key = value.toLowerCase()
            if (value === "" || value === typed || seen[key] === true) continue
            seen[key] = true
            out.push(value)
        }
        return out.slice(0, root.maxLocationSuggestions)
    }
    function searchLocations() {
        addressSearch.refresh()
        placeSearch.refresh()
    }
    component PlaceSearch: Process {
        id: search
        required property string source
        property string activeQuery: ""
        property var results: []
        function refresh() {
            if (root.locationQuery.length < root.minLocationQuery) {
                search.results = []
                return
            }
            if (search.running) return
            search.activeQuery = root.locationQuery
            search.command = [root.shell.home + "/.local/lib/hypr/calendar/places.sh", search.source, root.locationQuery]
            search.running = true
        }
        function clear() {
            search.running = false
            search.results = []
        }
        onRunningChanged: if (!running && search.activeQuery !== root.locationQuery) Qt.callLater(search.refresh)
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            if (search.activeQuery !== root.locationQuery) return
            try { search.results = JSON.parse(text) || [] } catch (error) { search.results = [] }
        } }
    }
    property PlaceSearch addressSearch: PlaceSearch { source: "ban" }
    property PlaceSearch placeSearch: PlaceSearch { source: "photon" }
    function clearLocationSearch() {
        addressSearch.clear()
        placeSearch.clear()
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

    function calendarsOnDate(date) {
        const entry = monthMarkersByDate[CalendarMath.isoDay(date)] || ({})
        return (entry.allDay || []).concat(entry.timed || []).filter((name, index, all) => all.indexOf(name) === index)
    }

    function loadSelectedDay() {
        if (!open) return
        selectedDayProcess.running = false
        selectedDayProcess.command = ["bash", root.agendaScript, "--day", CalendarMath.isoDay(selectedDate)]
        selectedDayProcess.running = true
    }
    function loadVisibleMonth() {
        if (!open) return
        visibleMonthProcess.running = false
        visibleMonthProcess.command = ["bash", root.agendaScript, "--month", Qt.formatDate(visibleMonth, "yyyy-MM")]
        visibleMonthProcess.running = true
    }
    function loadSelectedWeek() {
        if (!open || agendaMode !== "week") return
        selectedWeekProcess.running = false
        selectedWeekProcess.command = ["bash", root.agendaScript, "--week", selectedWeekStart]
        selectedWeekProcess.running = true
    }
    onSelectedWeekStartChanged: loadSelectedWeek()
    onAgendaModeChanged: {
        if (agendaMode === "week") agendaVisible = true
        loadSelectedWeek()
        persist()
    }
    property bool eventEditorOpen: false
    readonly property string noAlarm: "none"
    readonly property int timeStepSeconds: 15 * Units.SECONDS_PER_MINUTE
    readonly property var alarmChoices: [
        { label: "No alert", value: noAlarm }, { label: "At start", value: "0m" },
        { label: "10 minutes before", value: "10m" }, { label: "1 hour before", value: "1h" },
        { label: "1 day before", value: "1d" }
    ]
    readonly property var repeatChoices: [
        { label: "Does not repeat", value: "" }, { label: "Every day", value: "daily" },
        { label: "Every week", value: "weekly" }, { label: "Every month", value: "monthly" },
        { label: "Every year", value: "yearly" }
    ]
    property string defaultAlarm: ""
    property string defaultDayAlarm: ""
    property int defaultEventSeconds: Units.SECONDS_PER_HOUR
    property var draft: ({})
    readonly property string effectiveAlarm: draft.alarm ? draft.alarm : draft.allDay ? defaultDayAlarm : defaultAlarm
    readonly property var draftAlarmChoices: effectiveAlarm === "" || alarmChoices.some(choice => choice.value === effectiveAlarm) ? alarmChoices
        : alarmChoices.concat({ label: effectiveAlarm, value: effectiveAlarm })
    readonly property var writableCalendars: {
        const out = []
        for (const name in calendars)
            if (calendars[name].readonly !== true) out.push(name)
        out.sort()
        return out
    }
    signal saveRequested()
    property string editedEventUid: ""
    function alarmValueForTrigger(trigger) {
        const iso = /^([+-]?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(String(trigger))
        if (!iso) return noAlarm
        const delta = [[Number(iso[2] || 0) * 7 + Number(iso[3] || 0), "d"], [Number(iso[4] || 0), "h"], [Number(iso[5] || 0), "m"], [Number(iso[6] || 0), "s"]]
            .filter(part => part[0] > 0).map(part => part[0] + part[1]).join(" ")
        return delta === "" ? "0m" : (iso[1] === "-" ? "" : "-") + delta
    }
    function clockText(seconds) {
        return String(Math.floor(seconds / Units.SECONDS_PER_HOUR)).padStart(2, "0") + ":"
            + String(Math.floor(seconds % Units.SECONDS_PER_HOUR / Units.SECONDS_PER_MINUTE)).padStart(2, "0")
    }
    function shiftedDay(iso, days) {
        const day = CalendarMath.fromIsoDay(iso)
        day.setDate(day.getDate() + days)
        return CalendarMath.isoDay(day)
    }
    function daysBetween(fromIso, toIso) { return Math.round((CalendarMath.fromIsoDay(toIso) - CalendarMath.fromIsoDay(fromIso)) / Units.MS_PER_DAY) }
    function spanSeconds(startDay, startTime, endDay, endTime) {
        return daysBetween(startDay, endDay) * Units.SECONDS_PER_DAY + clockSeconds(endTime) - clockSeconds(startTime)
    }
    function endingAfter(startDay, startSeconds, lengthSeconds) {
        const end = startSeconds + lengthSeconds
        return { endDate: shiftedDay(startDay, Math.floor(end / Units.SECONDS_PER_DAY)), endTime: clockText(end % Units.SECONDS_PER_DAY) }
    }
    function nextStepSeconds() { return Math.min(nowSeconds + timeStepSeconds - nowSeconds % timeStepSeconds, Units.SECONDS_PER_DAY - timeStepSeconds) }
    function timeChoices(current, afterSeconds) {
        const values = []
        for (let seconds = afterSeconds >= 0 ? afterSeconds + timeStepSeconds - afterSeconds % timeStepSeconds : 0; seconds < Units.SECONDS_PER_DAY; seconds += timeStepSeconds)
            values.push(clockText(seconds))
        if (current && values.indexOf(current) < 0) values.push(current)
        values.sort()
        return values.map(value => ({ value: value, label: afterSeconds >= 0 ? value + "  ·  " + root.shell.duration(clockSeconds(value) - afterSeconds) : value }))
    }
    readonly property var startTimeChoices: timeChoices(draft.startTime, -1)
    readonly property var endTimeChoices: timeChoices(draft.endTime, draft.startDate === draft.endDate ? clockSeconds(draft.startTime) : -1)
    function updateDraft(patch) { draft = Object.assign({}, draft, patch) }
    function draftLengthSeconds() { return spanSeconds(draft.startDate, draft.startTime, draft.endDate, draft.endTime) }
    function setDraftStartDate(day) { updateDraft({ startDate: day, endDate: shiftedDay(draft.endDate, daysBetween(draft.startDate, day)) }) }
    function setDraftEndDate(day) { updateDraft({ endDate: day < draft.startDate ? draft.startDate : day }) }
    function setDraftStartTime(value) {
        const length = draftLengthSeconds()
        updateDraft(Object.assign({ startTime: value }, endingAfter(draft.startDate, clockSeconds(value), length > 0 ? length : defaultEventSeconds)))
    }
    function openEvent(event) {
        const uid = String(event.uid || "")
        if (!uid) return
        eventDetailsProcess.running = false
        eventDetailsProcess.command = ["bash", root.agendaScript, "--show", uid]
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
            const startDate = CalendarMath.rawDate(payload.startRaw) || CalendarMath.isoDay(root.selectedDate)
            const fallback = root.endingAfter(startDate, root.nextStepSeconds(), root.defaultEventSeconds)
            root.editedEventUid = root.requestedEventUid
            root.draft = {
                title: values.title, location: values.location, description: values.description,
                allDay: payload.allDay === true,
                startDate: startDate, startTime: values.start || root.clockText(root.nextStepSeconds()),
                endDate: values.endDay || startDate, endTime: values.end || fallback.endTime,
                alarm: root.alarmValueForTrigger(payload.alarm), repeat: String(payload.repeat || ""),
                calendar: root.requestedEventCalendar
            }
            root.eventEditorError = ""
            root.eventEditorOpen = true
        } }
    }
    function openNewEventEditor(values) {
        clearLocationSearch()
        eventDetailsOpen = false
        editedEventUid = ""
        eventEditorError = ""
        const timed = !(values && values.allDay)
        const startDate = values ? values.day : CalendarMath.isoDay(selectedDate)
        const startSeconds = values && timed ? clockSeconds(values.start) : nextStepSeconds()
        const fallback = endingAfter(startDate, startSeconds, defaultEventSeconds)
        draft = {
            title: values ? values.title : "", location: "", description: values ? values.description : "",
            allDay: !timed, startDate: startDate, startTime: clockText(startSeconds),
            endDate: values ? values.endDay || values.day : fallback.endDate,
            endTime: values && timed ? values.end : fallback.endTime,
            alarm: "", repeat: "", calendar: defaultCalendar
        }
        eventEditorOpen = true
    }
    function closeEventPanels() {
        clearLocationSearch()
        eventEditorOpen = false; editedEventUid = ""; draft = ({}); eventEditorError = ""
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
    function saveDraft(title, location, description) {
        const name = String(title).trim()
        if (name === "") {
            eventEditorError = "A title is required"
            return
        }
        if (draft.endDate < draft.startDate || !draft.allDay && draftLengthSeconds() <= 0) {
            eventEditorError = "The event ends before it starts"
            return
        }
        const args = ["--add", "--day", draft.startDate, "--title", name]
        if (!draft.allDay) args.push("--start", draft.startTime, "--end", draft.endTime)
        if (draft.endDate !== draft.startDate) args.push("--end-day", draft.endDate)
        const where = String(location).trim()
        if (where !== "") args.push("--location", where)
        const notes = String(description).trim()
        if (notes !== "") args.push("--description", notes)
        if (draft.alarm) args.push("--alarm", draft.alarm)
        if (draft.repeat) args.push("--repeat", draft.repeat)
        if (draft.calendar) args.push("--calendar", draft.calendar)
        if (editedEventUid !== "") args.push("--delete", editedEventUid)
        saveEvent(args)
    }
    function saveEvent(args) {
        eventEditorError = ""
        saveEventProcess.running = false
        saveEventProcess.command = ["bash", root.agendaScript].concat(args)
        saveEventProcess.running = true
    }

    function deleteEvent(uid) {
        if (!uid) return
        deleteEventProcess.running = false
        deleteEventProcess.command = ["bash", root.agendaScript, "--delete", String(uid), "--day", CalendarMath.isoDay(selectedDate)]
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
            root.eventSaved()
            if (payload.day !== CalendarMath.isoDay(root.selectedDate)) root.showDay(CalendarMath.fromIsoDay(payload.day))
            root.loadVisibleMonth()
        } }
    }

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
            root.defaultAlarm = String(payload.defaultAlarm || "")
            root.defaultDayAlarm = String(payload.defaultDayAlarm || "")
            root.defaultEventSeconds = Number(payload.defaultEventSeconds) || Units.SECONDS_PER_HOUR
            root.locations = payload.locations || []
        } }
    }
    function loadCalendars() {
        calendarMetadataProcess.running = false
        calendarMetadataProcess.command = ["bash", root.agendaScript, "--calendars"]
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

    Column {
        id: calendar
        width: root.calendarWidth
        spacing: Style.sectionGap
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
            case Qt.Key_J:        root.stepEvent(1); break
            case Qt.Key_K:        root.stepEvent(-1); break
            case Qt.Key_N:        root.agendaVisible = true; root.quickAddRequested(); break
            case Qt.Key_E:        if (root.selectedEvent && !root.eventIsReadOnly(root.selectedEvent)) root.openEvent(root.selectedEvent); break
            case Qt.Key_Return:
            case Qt.Key_Enter:    if (!root.selectedEvent) return; root.openEvent(root.selectedEvent); break
            case Qt.Key_Escape:   if (!root.selectedEvent) return; root.selectedEventIndex = -1; break
            default: return
            }
            event.accepted = true
        }

        Item {
            id: hero
            readonly property bool showsToday: root.selectedIsToday && root.visibleMonth.getMonth() === root.today.getMonth()
                && root.visibleMonth.getFullYear() === root.today.getFullYear()
            readonly property color tint: heroArea.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.foreground
            width: parent.width; height: heroRow.implicitHeight
            Row {
                id: heroRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.xxxl
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰃭"; color: hero.tint
                    font.family: root.shell.fontFamily; font.pixelSize: Style.heroIcon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(root.today, "MMMM d"); color: hero.tint
                    font.family: root.shell.fontFamily; font.pixelSize: Style.heroIcon; font.bold: true
                }
            }
            MouseArea {
                id: heroArea
                anchors.fill: heroRow
                enabled: !hero.showsToday
                hoverEnabled: enabled; cursorShape: Qt.PointingHandCursor
                onClicked: root.goToToday()
            }
        }
        Item {
            id: yearRail
            width: parent.width; height: Math.max(yearLabel.implicitHeight, Style.md)
            readonly property real progress: (root.today - new Date(root.today.getFullYear(), 0, 1)) / (new Date(root.today.getFullYear() + 1, 0, 1) - new Date(root.today.getFullYear(), 0, 1))

            Text {
                id: yearLabel
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear(); color: root.secondaryText
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.letterSpacing: 1
            }
            Text {
                id: yearPercent
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: Math.floor(yearRail.progress * 100) + "%"; color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Rectangle {
                anchors.left: yearLabel.right; anchors.right: yearPercent.left
                anchors.leftMargin: Style.xxl; anchors.rightMargin: Style.xxl
                anchors.verticalCenter: parent.verticalCenter
                height: Style.md; radius: root.shell.rounding > 0 ? height / 2 : 0
                color: root.structureLine
                Rectangle { width: parent.width * yearRail.progress; height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) }
            }
        }

        Item {
            width: parent.width; height: monthGrid.implicitHeight

            Rectangle {
                x: root.weekNumberColumnWidth + Math.round(root.weekGutterWidth / 2)
                y: root.weekdayHeaderHeight + monthGrid.spacing
                width: root.dividerWidth; height: monthGrid.implicitHeight - root.weekdayHeaderHeight - monthGrid.spacing
                color: root.structureLine
            }

        Grid {
            id: monthGrid
            width: parent.width; columns: 8; spacing: Style.xxs

            Item {
                width: root.weekNumberColumnWidth + root.weekGutterWidth; height: root.weekdayHeaderHeight
                Rectangle {
                    width: root.weekNumberColumnWidth; height: parent.height; radius: root.shell.rounding
                    color: weekStartMouse.containsMouse ? root.shell.hoverFill() : "transparent"
                    Text {
                        anchors.centerIn: parent; text: "W"
                        color: weekStartMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        font.bold: true; font.letterSpacing: 1
                    }
                    MouseArea {
                        id: weekStartMouse; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleWeekStart()
                    }
                }
            }
            Repeater {
                model: root.weekdayLabels
                Text {
                    required property var modelData
                    width: root.dayCellWidth; height: root.weekdayHeaderHeight; text: modelData
                    color: root.secondaryText
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1
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
                    readonly property bool inMonth: day.getMonth() === root.visibleMonth.getMonth()
                    readonly property var dots: isWeek ? [] : root.calendarsOnDate(day)

                    width: isWeek ? root.weekNumberColumnWidth + root.weekGutterWidth : root.dayCellWidth
                    height: root.dayCellHeight; radius: root.shell.rounding
                    color: hovered ? root.shell.hoverFill() : focused ? root.shell.selectedFill() : "transparent"
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

                    Text {
                        id: dayNumber
                        x: Math.round(((dayCell.isWeek ? root.weekNumberColumnWidth : dayCell.width) - width) / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: dayCell.dots.length > 0 ? -Style.xs : 0
                        text: dayCell.isWeek ? CalendarMath.isoWeek(dayCell.day) : dayCell.day.getDate()
                        color: dayCell.isWeek ? (dayCell.weekHovered ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.mutedText)
                            : dayCell.current ? root.shell.accent
                            : !dayCell.inMonth ? root.shell.faintText
                            : CalendarMath.isWeekend(CalendarMath.isoDay(dayCell.day)) ? root.secondaryText : root.shell.foreground
                        font.family: root.shell.fontFamily
                        font.pixelSize: dayCell.isWeek ? Style.caption : Style.body
                        font.bold: dayCell.current
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: dayNumber.bottom; anchors.topMargin: Style.px(1)
                        spacing: Style.px(1)
                        Repeater {
                            model: dayCell.dots
                            Rectangle {
                                required property var modelData
                                width: Style.xs; height: width; radius: width / 2
                                color: root.calendarColor(String(modelData), root.shell.role("act_br", root.shell.accent))
                                opacity: dayCell.inMonth ? 1 : Style.faintTextAlpha
                            }
                        }
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
                color: root.secondaryText
                font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.letterSpacing: 1
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.goToToday() }
            }
            ClockNavButton { popup: root; anchors.right: parent.right; anchors.rightMargin: Style.px(26); anchors.verticalCenter: parent.verticalCenter; glyph: "›"; onActivated: root.moveMonth(1) }
            ClockNavButton { popup: root; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "»"; onActivated: root.moveYear(1) }
        }

        WheelHandler { onWheel: event => { if (event.angleDelta.y) root.moveMonth(event.angleDelta.y > 0 ? -1 : 1) } }
        }

        Rectangle {
            visible: root.agendaVisible
            width: root.dividerWidth; height: Math.max(calendar.implicitHeight, agendaPane.height)
            color: root.structureLine
        }
        ClockAgendaPane { id: agendaPane; popup: root; calendarHeight: calendar.implicitHeight }
        }

}

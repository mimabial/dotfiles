import QtQuick
import QtQuick.Controls
import Quickshell.Io

PopupCard {
    id: root
    popupName: "clock"
    readonly property int calendarWidth: 440 - padding * 2
    readonly property int agendaWidth: 520
    readonly property int choiceColumn: 84
    readonly property int paneGap: 16
    property bool expanded: false
    contentWidth: calendarWidth + padding * 2 + (expanded ? agendaWidth + paneGap : 0)
    contentHeight: Math.max(calendar.implicitHeight, expanded ? agendaContent.implicitHeight : 0) + 32

    // bound, not sampled: the panel rolls over if left open past midnight
    readonly property date today: root.shell.clock.date
    property date viewDate: new Date(today.getFullYear(), today.getMonth(), 1)

    // Locale.Sunday === 0. The locale decides unless overridden; en_US says
    // Sunday, which is not what everyone wants.
    property int weekStartOverride: -1
    // memento mori: 0 means never set, and the rail stays hidden
    property int birthYear: 0
    property int lifeExpectancy: 90
    property bool editingLife: false
    readonly property int age: birthYear > 0 ? today.getFullYear() - birthYear : 0
    readonly property real lifeDone: (age > 0 && lifeExpectancy > 0) ? Math.max(0, Math.min(1, age / lifeExpectancy)) : 0
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
    function persist() {
        store.setText(JSON.stringify({
            weekStart: weekStartOverride, birthYear: birthYear, lifeExpectancy: lifeExpectancy
        }))
    }
    function toggleWeekStart() {
        weekStartOverride = weekStart === 1 ? 0 : 1
        persist()
    }
    function startEditingLife() {
        bornField.text = birthYear > 0 ? String(birthYear) : ""
        expectancyField.text = String(lifeExpectancy)
        editingLife = true
        bornField.forceActiveFocus(); bornField.selectAll()
    }
    function commitLife() {
        // a blank, absurd or non-numeric year means "not set"
        const born = parseInt(bornField.text, 10)
        const span = parseInt(expectancyField.text, 10)
        birthYear = (born > 1900 && born <= today.getFullYear()) ? born : 0
        lifeExpectancy = (span > 0 && span <= 150) ? span : 90
        editingLife = false
        persist()
    }
    function clearLife() { birthYear = 0; editingLife = false; persist() }
    function lifeKey(event, other) {
        if (event.key === Qt.Key_Escape) { editingLife = false; event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { commitLife(); event.accepted = true }
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            other.selectAll(); other.forceActiveFocus(); event.accepted = true
        }
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
    readonly property var agendaEvents: agenda.events || []
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
    function openEvent(uid) {
        if (!uid) return
        showProc.running = false
        showProc.command = ["hyprshell", "calendar/agenda", "--show", String(uid)]
        showProc.pendingUid = String(uid)
        showProc.running = true
    }
    property Process showProc: Process {
        property string pendingUid: ""
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            if (payload.error) { root.composeError = String(payload.error); return }
            root.editingUid = showProc.pendingUid
            root.composeAllDay = payload.allDay === true
            root.composeRepeat = String(payload.repeat || "")
            root.composeAlarm = root.alarmChoiceFor(payload.alarm)
            const lastDay = root.isoFromRaw(payload.endRaw)
            root.editingValues = {
                title: String(payload.title || ""),
                start: root.timeFromRaw(payload.startRaw),
                end: root.timeFromRaw(payload.endRaw),
                // an all-day DTEND is exclusive, so step it back for display
                endDay: payload.allDay === true ? root.previousDay(lastDay) : lastDay,
                location: String(payload.location || ""),
                description: String(payload.description || "")
            }
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
        editingUid = ""
        editingValues = ({})
        composeError = ""
        composeAllDay = false
        composeAlarm = ""
        composeRepeat = ""
        composing = true
    }
    function cancelCompose() { composing = false; editingUid = ""; editingValues = ({}); composeError = "" }
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

    component FieldLabel: Text {
        color: root.shell.alpha(root.shell.foreground, .45)
        font.family: root.shell.fontFamily; font.pixelSize: 9
        font.letterSpacing: 1; font.bold: true
    }
    component FormField: TextField {
        height: 24
        leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
        topPadding: 0; bottomPadding: 0
        color: root.shell.foreground
        placeholderTextColor: root.shell.alpha(root.shell.foreground, .28)
        font.family: root.shell.fontFamily; font.pixelSize: 11
        Keys.onEscapePressed: root.cancelCompose()
        readonly property bool masked: inputMask !== ""
        readonly property bool blank: !/\d/.test(text)
        onActiveFocusChanged: if (activeFocus && masked && blank) cursorPosition = 0
        onCursorPositionChanged: if (masked && blank && cursorPosition !== 0) cursorPosition = 0
        background: Rectangle {
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.foreground, .06)
            border.width: 1
            border.color: root.shell.alpha(root.shell.foreground, parent.activeFocus ? .45 : .18)
        }
    }
    component Chip: Rectangle {
        property alias text: chipText.text
        property bool selected: false
        signal picked
        implicitWidth: chipText.implicitWidth + Style.controlPaddingX * 2.5
        implicitHeight: 22
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
            font.family: root.shell.fontFamily; font.pixelSize: 10
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
            font.family: root.shell.fontFamily; font.pixelSize: 11
            background: null
            Keys.onEscapePressed: root.cancelCompose()
        }
    }

    component FormButton: Rectangle {
        property alias text: buttonText.text
        property bool primary: false
        signal activated
        implicitWidth: buttonText.implicitWidth + Style.controlPaddingX * 3
        implicitHeight: 24
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
            font.family: root.shell.fontFamily; font.pixelSize: 11
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent; enabled: parent.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    onOpenChanged: { if (open) { expanded = false; goToToday(); loadAgenda(); loadMonth() } else { editingLife = false; cancelCompose() } }

    property FileView store: FileView {
        path: root.shell.home + "/.local/state/quickshell/clock.json"
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.weekStartOverride = saved.weekStart !== undefined ? saved.weekStart : -1
                root.birthYear = saved.birthYear || 0
                root.lifeExpectancy = saved.lifeExpectancy || 90
            } catch (error) { root.weekStartOverride = -1 }
        }
    }

    component NavButton: Text {
        required property string glyph
        property real size: 24
        text: glyph
        color: root.shell.alpha(root.shell.foreground, mouse.containsMouse ? 1 : .75)
        font.family: root.shell.fontFamily; font.pixelSize: size
        signal activated
        MouseArea { id: mouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: parent.activated() }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.editingLife
        onClicked: root.editingLife = false
    }

    Row {
        anchors.fill: parent
        spacing: root.paneGap
        layoutDirection: root.position === "right" ? Qt.RightToLeft : Qt.LeftToRight

    Column {
        id: calendar
        width: root.calendarWidth
        spacing: 14
        focus: !root.editingLife && !root.composing

        Keys.onPressed: event => {
            if (root.composing || root.editingLife) return
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
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 38; font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Item {
            width: parent.width; height: root.editingLife ? 26 : 18
            readonly property real progress: (root.today - new Date(root.today.getFullYear(), 0, 1)) / (new Date(root.today.getFullYear() + 1, 0, 1) - new Date(root.today.getFullYear(), 0, 1))

            TapHandler { enabled: !root.editingLife; onDoubleTapped: root.startEditingLife() }

            Row {
                visible: root.editingLife
                anchors.centerIn: parent; spacing: 8
                Text {
                    height: 24; verticalAlignment: Text.AlignVCenter; text: "BORN"
                    color: Qt.darker(root.shell.foreground, 1.5)
                    font.family: root.shell.fontFamily; font.pixelSize: 9; font.letterSpacing: 1; font.bold: true
                }
                TextField {
                    id: bornField
                    width: 66; height: 24
                    leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
                    topPadding: 0; bottomPadding: 0
                    placeholderText: "year"; inputMethodHints: Qt.ImhDigitsOnly
                    color: root.shell.foreground
                    placeholderTextColor: Qt.darker(root.shell.foreground, 1.6)
                    font.family: root.shell.fontFamily; font.pixelSize: 10
                    background: Rectangle {
                        color: root.shell.alpha(root.shell.foreground, .07)
                        radius: root.shell.rounding
                    }
                    Keys.onPressed: event => root.lifeKey(event, expectancyField)
                }
                Text {
                    height: 24; verticalAlignment: Text.AlignVCenter; text: "LIVE TO"
                    color: Qt.darker(root.shell.foreground, 1.5)
                    font.family: root.shell.fontFamily; font.pixelSize: 9; font.letterSpacing: 1; font.bold: true
                }
                TextField {
                    id: expectancyField
                    width: 56; height: 24
                    leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
                    topPadding: 0; bottomPadding: 0
                    placeholderText: "90"; inputMethodHints: Qt.ImhDigitsOnly
                    color: root.shell.foreground
                    placeholderTextColor: Qt.darker(root.shell.foreground, 1.6)
                    font.family: root.shell.fontFamily; font.pixelSize: 10
                    background: Rectangle {
                        color: root.shell.alpha(root.shell.foreground, .07)
                        radius: root.shell.rounding
                    }
                    Keys.onPressed: event => root.lifeKey(event, bornField)
                }
            }

            Text { visible: !root.editingLife; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.today.getFullYear(); color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: 10 }
            Text { visible: !root.editingLife; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.floor(parent.progress * 100) + "%"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 10 }
            Rectangle { visible: !root.editingLife; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 42; anchors.rightMargin: 34; anchors.verticalCenter: parent.verticalCenter; height: 5; radius: 3; color: root.shell.alpha(root.shell.foreground, .12); Rectangle { width: parent.width * parent.parent.progress; height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) } }
        }

        Item {
            visible: root.birthYear > 0 && !root.editingLife
            width: parent.width; height: visible ? 18 : 0

            TapHandler { onDoubleTapped: root.clearLife() }

            Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "LIFE"; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: 10; font.letterSpacing: 1 }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: Math.floor(root.lifeDone * 100) + "%"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 10 }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 42; anchors.rightMargin: 34
                anchors.verticalCenter: parent.verticalCenter
                height: 5; radius: 3; color: root.shell.alpha(root.shell.foreground, .12)
                Rectangle {
                    width: parent.width * root.lifeDone; height: parent.height; radius: parent.radius
                    color: root.shell.role("act_br", root.shell.accent)
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }
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
                width: root.weekColumn; height: 18; radius: root.shell.rounding
                color: weekStartMouse.containsMouse ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), .18) : "transparent"
                Text {
                    anchors.centerIn: parent; text: "W"
                    color: weekStartMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : Qt.darker(root.shell.foreground, 1.9)
                    font.family: root.shell.fontFamily; font.pixelSize: 9
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
                    width: root.cellWidth; height: 18; text: modelData
                    color: root.shell.alpha(root.shell.foreground, .45)
                    font.family: root.shell.fontFamily; font.pixelSize: 9; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Repeater {
                model: 48
                Rectangle {
                    required property int index
                    readonly property int column: index % 8
                    readonly property bool isWeek: column === 0
                    readonly property date day: root.dateAt(Math.floor(index / 8) * 7 + Math.max(0, column - 1))
                    readonly property bool current: !isWeek && root.sameDay(day, root.today)
                    readonly property bool focused: !isWeek && root.sameDay(day, root.cursor)

                    readonly property bool hovered: !isWeek && dayArea.containsMouse

                    width: isWeek ? root.weekColumn : root.cellWidth
                    height: 31; radius: root.shell.rounding
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
                        enabled: !parent.isWeek
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const already = root.sameDay(parent.day, root.cursor)
                            root.cursor = parent.day
                            if (parent.day.getMonth() !== root.viewDate.getMonth())
                                root.viewDate = new Date(parent.day.getFullYear(), parent.day.getMonth(), 1)
                            root.expanded = already ? !root.expanded : true
                        }
                    }

                    Rectangle {
                        visible: !parent.isWeek && (root.monthDays[root.isoDay(parent.day)] || 0) > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        width: 4; height: 4; radius: 2
                        color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), .9)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.isWeek ? root.isoWeek(parent.day) : parent.day.getDate()
                        color: parent.isWeek ? root.shell.alpha(root.shell.foreground, .3)
                            : parent.day.getMonth() === root.viewDate.getMonth() ? root.shell.foreground
                            : root.shell.alpha(root.shell.foreground, .25)
                        font.family: root.shell.fontFamily
                        font.pixelSize: parent.isWeek ? 9 : 12
                        font.bold: parent.current
                    }
                }
            }
        }
        }
        Item {
            width: parent.width; height: 24
            NavButton { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; glyph: "«"; onActivated: root.moveYear(-1) }
            NavButton { anchors.left: parent.left; anchors.leftMargin: 26; anchors.verticalCenter: parent.verticalCenter; glyph: "‹"; onActivated: root.moveMonth(-1) }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: root.shell.alpha(root.shell.foreground, .7)
                font.family: root.shell.fontFamily; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.goToToday() }
            }
            NavButton { anchors.right: parent.right; anchors.rightMargin: 26; anchors.verticalCenter: parent.verticalCenter; glyph: "›"; onActivated: root.moveMonth(1) }
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
            spacing: 10

        Text {
            id: agendaTitle
            width: parent.width
            text: root.editingUid !== ""
                ? "EDITING \u2014 " + Qt.formatDate(root.cursor, "dddd d MMMM").toUpperCase()
                : Qt.formatDate(root.cursor, "dddd d MMMM").toUpperCase()
            color: root.shell.alpha(root.shell.foreground, .55)
            font.family: root.shell.fontFamily; font.pixelSize: 9
            font.letterSpacing: 1; font.bold: true
        }
        Text {
            visible: root.agendaEvents.length === 0 && !root.composing
            width: parent.width
            text: root.agenda.unavailable === true ? "khal is not configured" : "Nothing scheduled"
            color: root.shell.alpha(root.shell.foreground, .35)
            font.family: root.shell.fontFamily; font.pixelSize: 11
        }
        Column {
            visible: !root.composing
            width: parent.width; spacing: 3
            Repeater {
                model: root.agendaEvents
                Item {
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
                        onClicked: root.openEvent(parent.modelData.uid)
                    }

                    Row {
                    id: eventRow
                    width: parent.width; spacing: Style.sm
                    Text {
                        width: 40
                        text: parent.parent.modelData.allDay ? "all" : parent.parent.modelData.start
                        color: root.shell.alpha(root.shell.foreground, .55)
                        font.family: root.shell.fontFamily; font.pixelSize: 11
                    }
                    Column {
                        readonly property var modelData: parent.parent.modelData
                        width: parent.width - 40 - Style.sm - 22; spacing: 0
                        Text {
                            width: parent.width; text: modelData.title; elide: Text.ElideRight
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: 11
                        }
                        Row {
                            width: parent.width; spacing: Style.xs
                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: [parent.parent.modelData.location, parent.parent.modelData.description].filter(part => !!part).join("  ·  ")
                                elide: Text.ElideRight
                                color: root.shell.alpha(root.shell.foreground, .4)
                                font.family: root.shell.fontFamily; font.pixelSize: 9
                            }
                        }
                    }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: eventHover.hovered
                        width: 20; height: 20; radius: root.shell.rounding
                        color: binArea.containsMouse
                            ? root.shell.alpha(root.shell.role("error", root.shell.foreground), .25) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0a7a}"
                            color: binArea.containsMouse ? root.shell.role("error", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .6)
                            font.family: root.shell.fontFamily; font.pixelSize: 11
                        }
                        MouseArea {
                            id: binArea
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.deleteEvent(parent.parent.modelData.uid)
                        }
                    }
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
                                Text { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 24
                                    text: "→"; color: root.shell.alpha(root.shell.foreground, .35)
                                    font.family: root.shell.fontFamily; font.pixelSize: 11
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
                            id: locationField; width: parent.width
                            text: root.editingValues.location || ""; placeholderText: "Location (optional)"
                            Keys.onReturnPressed: descriptionField.forceActiveFocus()
                            Keys.onEnterPressed: descriptionField.forceActiveFocus()
                        }

                        FormArea {
                            id: descriptionField; width: parent.width; lines: 4
                            text: root.editingValues.description || ""; placeholderText: "Description (optional)"
                        }

                        Item { width: 1; height: Style.xs }

                        Row {
                            width: parent.width; height: 22; spacing: Style.sm
                            FieldLabel { id: alertLabel; width: root.choiceColumn - Style.controlPaddingX * 2; height: parent.height; text: "ALERT"; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: root.alarmChoices
                                Chip {
                                    required property var modelData
                                    width: (parent.width - alertLabel.width - parent.spacing * root.alarmChoices.length) / root.alarmChoices.length
                                    text: modelData.label; selected: root.composeAlarm === modelData.value
                                    onPicked: root.composeAlarm = modelData.value
                                }
                            }
                        }
                        Row {
                            width: parent.width; height: 22; spacing: Style.sm
                            FieldLabel { id: repeatLabel; width: alertLabel.width; height: parent.height; text: "REPEAT"; verticalAlignment: Text.AlignVCenter }
                            Repeater {
                                model: root.repeatChoices
                                Chip {
                                    required property var modelData
                                    width: (parent.width - repeatLabel.width - parent.spacing * root.repeatChoices.length) / root.repeatChoices.length
                                    text: modelData.label; selected: root.composeRepeat === modelData.value
                                    onPicked: root.composeRepeat = modelData.value
                                }
                            }
                        }

                        Item { width: 1; height: Style.xs }

                        Item {
                            width: parent.width; height: 24
                            Text {
                                visible: root.composeError !== ""
                                anchors.left: parent.left; anchors.right: formButtons.left; anchors.rightMargin: Style.sm
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f002a}  " + root.composeError; elide: Text.ElideRight
                                color: root.shell.role("error", root.shell.foreground)
                                font.family: root.shell.fontFamily; font.pixelSize: 10
                            }
                            Row {
                                id: formButtons; anchors.right: parent.right; spacing: Style.lg
                                FormButton { width: root.choiceColumn; text: "Cancel"; onActivated: root.cancelCompose() }
                                FormButton {
                                    width: root.choiceColumn; text: root.editingUid !== "" ? "Save" : "Add"; primary: true
                                    onActivated: root.saveEvent({
                                        title: titleField.text, start: startField.text,
                                        end: endField.text, endDay: endDayField.text,
                                        location: locationField.text, description: descriptionField.text
                                    })
                                }
                            }
                        }
                    }
                    Component.onCompleted: titleField.forceActiveFocus()
                }
            }
        }

        Rectangle {
            width: parent.width; height: 26
            visible: !root.composing
            radius: root.shell.rounding
            color: addArea.containsMouse ? root.shell.alpha(root.shell.foreground, .1) : "transparent"
            border.width: addArea.containsMouse ? 1 : 0
            border.color: root.shell.alpha(root.shell.foreground, .25)
            Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: "\u{f0415}  Add event"
                color: root.shell.alpha(root.shell.foreground, addArea.containsMouse ? .9 : .45)
                font.family: root.shell.fontFamily; font.pixelSize: 11
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

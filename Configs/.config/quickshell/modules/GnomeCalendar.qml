pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../CalendarMath.js" as CalendarMath
import ".."

Column {
    id: root
    required property var shell
    required property Item anchorItem
    required property bool active
    property bool showWeekNumbers: false
    readonly property int daysPerWeek: 7
    readonly property date today: new Date(shell.clock.date.getFullYear(), shell.clock.date.getMonth(), shell.clock.date.getDate())
    property date selectedDate: today
    property date visibleMonth: new Date(today.getFullYear(), today.getMonth(), 1)
    property int weekStart: Qt.locale().firstDayOfWeek
    readonly property int thursdayColumn: (Qt.Thursday - weekStart + daysPerWeek) % daysPerWeek
    readonly property date firstShown: CalendarMath.startOfWeek(visibleMonth, weekStart)
    readonly property int weeks: Math.ceil((Math.round((new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 0) - firstShown) / CalendarMath.MS_PER_DAY) + 1) / daysPerWeek)
    readonly property int gridColumns: daysPerWeek + (showWeekNumbers ? 1 : 0)
    readonly property real cellSpacing: Style.xxs
    readonly property real cellWidth: (width - cellSpacing * (gridColumns - 1)) / gridColumns
    property var events: []
    property var eventDays: ({})
    property string agendaDay: ""
    property string agendaMonth: ""
    spacing: Style.sectionGap
    function dayAt(offset) { return new Date(firstShown.getFullYear(), firstShown.getMonth(), firstShown.getDate() + offset) }
    function moveMonth(delta) { visibleMonth = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + delta, 1) }
    function goToToday() {
        visibleMonth = new Date(today.getFullYear(), today.getMonth(), 1)
        selectedDate = today
    }
    function loadAgenda() {
        if (!active || agenda.running) return
        agendaDay = CalendarMath.isoDay(selectedDate)
        agenda.command = ["bash", shell.home + "/.local/lib/hypr/calendar/agenda.sh", "--day", agendaDay]
        agenda.running = true
    }
    function loadEventDays() {
        if (!active || monthAgenda.running) return
        agendaMonth = Qt.formatDate(visibleMonth, "yyyy-MM")
        monthAgenda.command = ["bash", shell.home + "/.local/lib/hypr/calendar/agenda.sh", "--month", agendaMonth]
        monthAgenda.running = true
    }
    onSelectedDateChanged: loadAgenda()
    onVisibleMonthChanged: loadEventDays()
    onActiveChanged: if (active) { goToToday(); loadAgenda(); loadEventDays() }
    Component.onCompleted: { loadAgenda(); loadEventDays() }
    component Label: Text {
        color: root.shell.foreground
        font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true
    }
    component SectionButton: Rectangle {
        id: section
        default property alias content: body.data
        readonly property bool navigable: true
        property bool cursored: false
        signal clicked()
        width: parent.width
        implicitHeight: body.implicitHeight + Style.sm * 2
        radius: root.shell.rounding
        color: cursored ? root.shell.hoverFill() : "transparent"
        border.width: root.shell.borderWidth
        border.color: cursored ? root.shell.hoverEdge() : "transparent"
        Column { id: body; x: Style.sm; y: Style.sm; width: parent.width - Style.sm * 2; spacing: Style.sm }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: section.clicked() }
        PopupPointer { shell: root.shell; row: section }
    }
    SectionButton {
        onClicked: root.goToToday()
        Label { text: Qt.formatDate(root.today, "dddd"); color: root.shell.mutedText }
        Label { text: Qt.formatDate(root.today, "MMMM d yyyy"); font.pixelSize: Style.title }
    }
    Row {
        width: parent.width
        Label { width: parent.width - previous.width - next.width; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDate(root.visibleMonth, "MMMM yyyy") }
        PopupIconButton { id: previous; shell: root.shell; glyph: "󰅁"; hint: "Previous month"; onClicked: root.moveMonth(-1) }
        PopupIconButton { id: next; shell: root.shell; glyph: "󰅂"; hint: "Next month"; onClicked: root.moveMonth(1) }
    }
    Column {
        width: parent.width; spacing: root.cellSpacing
        Row {
            spacing: root.cellSpacing
            Item { visible: root.showWeekNumbers; width: root.cellWidth }
            Repeater {
                model: root.daysPerWeek
                Label {
                    required property int index
                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.caption
                    text: Qt.locale().dayName((root.weekStart + index) % root.daysPerWeek, Locale.NarrowFormat)
                }
            }
        }
        Repeater {
            model: root.weeks
            Row {
                id: week
                required property int index
                readonly property int firstDayOffset: index * root.daysPerWeek
                spacing: root.cellSpacing
                Label {
                    visible: root.showWeekNumbers
                    width: root.cellWidth; anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.caption; color: root.shell.mutedText
                    text: CalendarMath.isoWeek(root.dayAt(week.firstDayOffset + root.thursdayColumn))
                }
                Repeater {
                    model: root.daysPerWeek
                    PopupTab {
                        id: dayTab
                        required property int index
                        readonly property date day: root.dayAt(week.firstDayOffset + index)
                        width: root.cellWidth
                        shell: root.shell; text: String(day.getDate()); selected: CalendarMath.sameDay(day, root.selectedDate)
                        opacity: day.getMonth() === root.visibleMonth.getMonth() ? 1 : Style.mutedTextAlpha
                        onClicked: root.selectedDate = day
                        Rectangle {
                            visible: !!root.eventDays[CalendarMath.isoDay(dayTab.day)]
                            width: Style.xs; height: width; radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: Style.xxs
                            color: root.shell.foreground
                        }
                    }
                }
            }
        }
    }
    PopupSeparator { shell: root.shell }
    SectionButton {
        onClicked: root.shell.togglePopup("clock")
        Label { text: CalendarMath.sameDay(root.selectedDate, root.today) ? "Today" : Qt.formatDate(root.selectedDate, "dddd, MMMM d") }
        Label { visible: root.events.length === 0; text: "No Events"; color: root.shell.mutedText; font.bold: false }
        Repeater {
            model: root.events
            PopupRow {
                required property var modelData
                width: parent.width; shell: root.shell; interactive: false; title: modelData.title || ""
                detail: modelData.allDay ? "All Day" : [modelData.start, modelData.end].filter(Boolean).join(" – ")
            }
        }
    }
    SectionButton {
        visible: !!Weather.data.current_condition?.length
        onClicked: root.shell.togglePopup("weather")
        Label { text: "Weather" }
        PopupRow {
            width: parent.width; shell: root.shell; interactive: false
            title: String(Weather.data.nearest_area?.[0]?.areaName?.[0]?.value ?? "")
            detail: String(Weather.data.current_condition?.[0]?.[Weather.imperial ? "temp_F" : "temp_C"] ?? "") + (Weather.imperial ? "°F" : "°C") + " · " + String(Weather.data.current_condition?.[0]?.weatherDesc?.[0]?.value ?? "")
        }
    }
    Process {
        id: agenda
        onExited: if (root.active && root.agendaDay !== CalendarMath.isoDay(root.selectedDate)) root.loadAgenda()
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const report = JSON.parse(text)
                if (report.day === CalendarMath.isoDay(root.selectedDate)) root.events = report.events || []
            }
            catch (error) { console.warn("calendar agenda: " + error) }
        } }
    }
    Process {
        id: monthAgenda
        onExited: if (root.active && root.agendaMonth !== Qt.formatDate(root.visibleMonth, "yyyy-MM")) root.loadEventDays()
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const report = JSON.parse(text)
                if (report.month === root.agendaMonth) root.eventDays = report.days || {}
            }
            catch (error) { console.warn("calendar month agenda: " + error) }
        } }
    }
    FileView {
        path: root.shell.home + "/.local/state/quickshell/clock.json"; watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const saved = JSON.parse(text())
            root.weekStart = saved.weekStart >= 0 ? saved.weekStart : Qt.locale().firstDayOfWeek
        }
    }
    LazyPopup { shell: root.shell; popup: "weather"; owners: ["weather"]; sourceComponent: Component { WeatherPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: true } } }
}

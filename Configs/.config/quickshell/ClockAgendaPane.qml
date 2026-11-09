pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons as Commons
import "CalendarMath.js" as CalendarMath

Item {
    id: pane
    readonly property int maxChips: 3
    required property var popup
    required property real calendarHeight
    readonly property int timeColumnWidth: Style.px(40)
    readonly property int previewLabelWidth: Style.px(52)
    readonly property int formLabelWidth: Style.px(64)
    readonly property string quickAddHelp: [
        "Day or time first, then the title",
        "Day: today, tomorrow, friday, 2026-11-12",
        "Time: 14:00, or 14:00 15:30 with an end",
        "Length: 45m, 1h30m, or 3d for several days",
        "Several days: 2026-11-12 2026-11-14 Trip",
        "Timezone: 14:00 Europe/London Call",
        "Notes: tomorrow 9:00 Dentist :: bring card",
        "A time alone goes on the selected day",
        "A day alone makes an all-day event"
    ].join("\n")
    width: pane.popup.agendaVisible ? pane.popup.agendaWidth : 0
    height: agendaContent.implicitHeight
    visible: pane.popup.agendaVisible
    clip: true

    component FieldLabel: Text {
        color: pane.popup.shell.mutedText
        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
        font.letterSpacing: 1; font.bold: true
    }
    component FormField: PopupField {
        shell: pane.popup.shell
        Keys.onEscapePressed: pane.popup.closeEventPanels()
        onSubmitted: pane.popup.saveRequested()
    }
    component Chip: Rectangle {
        property alias text: chipText.text
        property bool selected: false
        signal picked
        implicitWidth: chipText.implicitWidth + Style.controlPaddingX * 2.5
        implicitHeight: Style.px(22)
        radius: pane.popup.shell.rounding
        color: chipArea.containsMouse ? pane.popup.shell.hoverFill() : selected ? pane.popup.shell.selectedFill() : "transparent"
        border.width: 1
        border.color: pane.popup.structureLine
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Text {
            id: chipText
            anchors.centerIn: parent
            color: parent.selected ? pane.popup.shell.foreground : pane.popup.secondaryText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
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
        ScrollBar.vertical.opacity: Style.popupStyle.scrollbarAlpha
        ScrollBar.horizontal.opacity: Style.popupStyle.scrollbarAlpha
        background: Rectangle {
            radius: pane.popup.shell.rounding
            color: area.activeFocus ? pane.popup.shell.hoverFill() : pane.popup.shell.alpha(pane.popup.shell.foreground, Style.fieldFillAlpha)
            border.width: 1
            border.color: pane.popup.structureLine
        }
        TextArea {
            id: area
            wrapMode: TextArea.Wrap
            leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
            topPadding: Style.controlPaddingY; bottomPadding: Style.controlPaddingY
            color: pane.popup.shell.foreground
            placeholderTextColor: pane.popup.shell.faintText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
            background: null
            Keys.onEscapePressed: pane.popup.closeEventPanels()
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && (event.modifiers & Qt.ControlModifier)) {
                        pane.popup.saveRequested()
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
        radius: pane.popup.shell.rounding
        opacity: enabled ? 1 : Style.faintTextAlpha
        color: buttonArea.containsMouse ? pane.popup.shell.hoverFill() : primary ? pane.popup.shell.selectedFill() : "transparent"
        border.width: 1
        border.color: pane.popup.structureLine
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Text {
            id: buttonText
            anchors.centerIn: parent
            color: pane.popup.shell.foreground
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent; enabled: parent.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    component FieldRow: Row {
        id: fieldRow
        property alias label: rowLabel.text
        default property alias content: slot.data
        readonly property real slotWidth: width - pane.formLabelWidth - spacing
        readonly property real halfSlot: Math.floor((slotWidth - slot.spacing) / 2)
        width: parent ? parent.width : 0
        spacing: Style.md
        FieldLabel { id: rowLabel; width: pane.formLabelWidth; height: Style.controlHeight; verticalAlignment: Text.AlignVCenter }
        Row { id: slot; height: Math.max(Style.controlHeight, implicitHeight); spacing: Style.md }
    }

    component KeyCap: Rectangle {
        property alias text: keyLabel.text
        property bool highlighted: false
        width: Math.max(height, keyLabel.implicitWidth + Style.md * 2)
        height: keyLabel.implicitHeight + Style.xxs * 2
        radius: pane.popup.shell.rounding
        color: pane.popup.shell.hoverFill(highlighted ? 2 : 1)
        Text {
            id: keyLabel
            anchors.centerIn: parent
            color: parent.highlighted ? pane.popup.shell.foreground : pane.popup.secondaryText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    component Dot: Rectangle {
        width: Style.md; height: width; radius: width / 2
    }

    component BinButton: Rectangle {
        id: bin
        property string uid: ""
        width: Style.px(20); height: width; radius: pane.popup.shell.rounding
        color: binArea.containsMouse ? pane.popup.shell.alpha(pane.popup.shell.role("error", pane.popup.shell.foreground), Style.hoverFillAlpha) : "transparent"
        Text {
            anchors.centerIn: parent
            text: "\u{f0a7a}"
            color: binArea.containsMouse ? pane.popup.shell.role("error", pane.popup.shell.foreground) : pane.popup.shell.mutedText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: binArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: pane.popup.deleteEvent(bin.uid)
        }
    }

    component AgendaRow: Rectangle {
        id: row
        property var event: ({})
        property int itemIndex: -1
        readonly property string phase: event.allDay ? "" : pane.popup.eventPhase(event)
        readonly property string countdown: event.allDay ? "" : pane.popup.countdownText(event)
        readonly property bool soon: !event.allDay && pane.popup.startsSoon(event)
        readonly property string note: [pane.popup.secondaryCalendarName(event), event.location, event.description].filter(part => !!part).join("  ·  ")
        width: parent ? parent.width : 0
        implicitHeight: Math.max(lines.implicitHeight, times.implicitHeight) + Style.lg * 2
        radius: pane.popup.shell.rounding
        color: rowHover.hovered ? pane.popup.shell.hoverFill() : itemIndex === pane.popup.selectedEventIndex ? pane.popup.shell.selectedFill() : "transparent"
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        HoverHandler { id: rowHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pane.popup.openEvent(row.event)
        }
        Item {
            anchors.fill: parent
            opacity: row.phase === "past" ? Style.faintTextAlpha : 1
            Column {
                id: times
                visible: !row.event.allDay
                x: Style.lg; y: Style.lg
                width: visible ? pane.timeColumnWidth : 0
                spacing: Style.px(1)
                Text {
                    text: String(row.event.start || "")
                    color: row.phase === "now" ? pane.popup.shell.accent : pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.body
                }
                Text {
                    text: String(row.event.end || "")
                    color: pane.popup.shell.mutedText
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
            Dot {
                id: dot
                x: times.x + times.width + (row.event.allDay ? 0 : Style.sm)
                y: Style.lg + Style.sm
                color: pane.popup.eventChipColor(row.event)
            }
            Column {
                id: lines
                anchors.left: dot.right; anchors.right: parent.right
                anchors.leftMargin: Style.lg; anchors.rightMargin: bin.width + Style.lg
                y: Style.lg
                spacing: Style.xxs
                Text {
                    width: parent.width
                    text: String(row.event.title || "")
                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.body
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    text: row.countdown
                    color: row.soon ? pane.popup.shell.accent : pane.popup.shell.mutedText
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption; font.bold: row.soon
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    text: row.note
                    elide: Text.ElideRight
                    color: pane.popup.shell.mutedText
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }
        BinButton {
            id: bin
            anchors.right: parent.right; anchors.rightMargin: Style.md
            anchors.verticalCenter: parent.verticalCenter
            uid: String(row.event.uid || "")
            visible: rowHover.hovered && !pane.popup.eventIsReadOnly(row.event)
        }
    }

    component NowLine: Item {
        width: parent ? parent.width : 0
        height: nowLabel.implicitHeight
        Dot {
            id: nowDot
            x: Style.sm; anchors.verticalCenter: parent.verticalCenter
            color: pane.popup.shell.accent
        }
        Text {
            id: nowLabel
            anchors.left: nowDot.right; anchors.leftMargin: Style.md
            text: Qt.formatTime(pane.popup.today, "HH:mm")
            color: pane.popup.shell.accent
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
        }
        Rectangle {
            anchors.left: nowLabel.right; anchors.right: parent.right
            anchors.leftMargin: Style.md; anchors.verticalCenter: parent.verticalCenter
            height: Style.xxs; radius: height / 2
            color: pane.popup.shell.accent
        }
    }

    Column {
    id: agendaContent
    anchors.right: parent.right
    width: pane.popup.agendaWidth
    spacing: Style.sectionGap

Column {
    width: parent.width; spacing: Style.sm
    visible: !pane.popup.eventPanelOpen
    PopupField {
        id: quickField
        shell: pane.popup.shell
        width: parent.width
        leftPadding: quickIcon.x + quickIcon.width + Style.lg
        rightPadding: quickKeys.width + Style.controlPaddingX + Style.lg
        placeholderText: "New… tomorrow 14:00 1h Lunch"
        function submit(event) { if (event.modifiers & Qt.ShiftModifier) pane.popup.editQuickAdd(); else pane.popup.quickAdd() }
        onSubmitted: pane.popup.quickAdd()
        Keys.onReturnPressed: event => quickField.submit(event)
        Keys.onEnterPressed: event => quickField.submit(event)
        Keys.onEscapePressed: { if (quickField.text !== "") quickField.clear(); else pane.popup.focusCalendar() }
        Text {
            id: quickIcon
            x: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0415}"
            color: quickIconArea.containsMouse ? pane.popup.shell.role("hvr_fg", pane.popup.shell.foreground) : pane.popup.shell.accent
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.body
            MouseArea {
                id: quickIconArea
                anchors.fill: parent; anchors.margins: -Style.sm
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: pane.popup.editQuickAdd()
            }
        }
        Row {
            id: quickKeys
            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.sm
            KeyCap {
                text: "?"
                highlighted: helpHover.hovered
                HoverHandler { id: helpHover; cursorShape: Qt.WhatsThisCursor }
                ToolTip {
                    visible: helpHover.hovered
                    delay: Style.tooltipDelay
                    padding: Style.lg
                    text: pane.quickAddHelp
                    background: Rectangle {
                        radius: pane.popup.shell.rounding
                        color: pane.popup.shell.alpha(Style.popupTinted(pane.popup.shell.role("bg", pane.popup.shell.background)), .98)
                        border.width: 1; border.color: Style.popupBorder(pane.popup.shell.role("alt_br", pane.popup.shell.foreground), .45)
                    }
                    contentItem: Text {
                        text: pane.quickAddHelp
                        color: pane.popup.shell.foreground
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                }
            }
            KeyCap { visible: !quickField.activeFocus; text: "N" }
        }
    }
    Rectangle {
        visible: pane.popup.quickRows.length > 0 || pane.popup.quickError !== ""
        width: parent.width; height: previewColumn.implicitHeight + Style.lg * 2
        radius: pane.popup.shell.rounding
        color: pane.popup.shell.alpha(pane.popup.shell.foreground, Style.fieldFillAlpha)
        border.width: 1
        border.color: pane.popup.structureLine
        Column {
            id: previewColumn
            x: Style.controlPaddingX; y: Style.lg
            width: parent.width - Style.controlPaddingX * 2
            spacing: Style.xs
            Text {
                visible: text !== ""
                width: parent.width; wrapMode: Text.Wrap
                text: pane.popup.quickError
                color: pane.popup.shell.role("error", pane.popup.shell.foreground)
                font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
            }
            Repeater {
                model: pane.popup.quickRows
                Row {
                    id: previewRow
                    required property var modelData
                    width: previewColumn.width; spacing: Style.lg
                    FieldLabel { width: pane.previewLabelWidth; text: previewRow.modelData.label; topPadding: Style.px(1) }
                    Text {
                        width: parent.width - pane.previewLabelWidth - parent.spacing
                        text: previewRow.modelData.value; wrapMode: Text.Wrap
                        color: pane.popup.shell.foreground
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                        font.bold: previewRow.modelData.label === "TITLE"
                    }
                }
            }
            Item {
                visible: pane.popup.quickRows.length > 0
                width: parent.width; height: quickButtons.height + Style.xs
                Text {
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    anchors.right: quickButtons.left; anchors.rightMargin: Style.lg
                    text: pane.popup.defaultCalendar; elide: Text.ElideRight
                    color: pane.popup.shell.mutedText
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
                Row {
                    id: quickButtons
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    spacing: Style.md
                    FormButton { text: "More options"; onActivated: pane.popup.editQuickAdd() }
                    FormButton { text: "Add  ⏎"; primary: true; onActivated: pane.popup.quickAdd() }
                }
            }
        }
    }
    Binding { target: pane.popup; property: "quickText"; value: quickField.text }
    Binding { target: pane.popup; property: "quickAddFocused"; value: quickField.activeFocus }
    Connections {
        target: pane.popup
        function onQuickAddRequested() { quickField.forceActiveFocus() }
        function onEventSaved() { quickField.clear() }
    }
}

Rectangle {
    id: nextCard
    readonly property var event: pane.popup.shell.upcomingEvents.nextUp
    readonly property bool live: event !== null && event === pane.popup.shell.upcomingEvents.current
    visible: event !== null && !pane.popup.eventPanelOpen
    width: parent.width; height: nextColumn.implicitHeight + Style.xxl * 2
    radius: pane.popup.shell.rounding
    color: nextArea.containsMouse ? pane.popup.shell.hoverFill() : pane.popup.shell.selectedFill()
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    Column {
        id: nextColumn
        x: Style.xxxl; y: Style.xxl
        width: parent.width - Style.xxxl * 2
        spacing: Style.xs
        FieldLabel {
            text: !nextCard.event ? "" : nextCard.live ? "HAPPENING NOW"
                : "NEXT  ·  IN " + pane.popup.shell.duration(pane.popup.shell.upcomingEvents.secondsUntil(nextCard.event)).toUpperCase()
            color: pane.popup.shell.accent
        }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: nextCard.event ? String(nextCard.event.title || "") : ""
            color: pane.popup.shell.foreground
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.title; font.bold: true
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: !nextCard.event ? "" : [Qt.formatTime(new Date(pane.popup.shell.upcomingEvents.ms(nextCard.event.start)), "HH:mm")
                + " – " + Qt.formatTime(new Date(pane.popup.shell.upcomingEvents.ms(nextCard.event.end)), "HH:mm"),
                nextCard.event.location].filter(part => !!part).join("  ·  ")
            color: pane.popup.shell.mutedText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
    }
    MouseArea {
        id: nextArea
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: pane.popup.openUpcoming(nextCard.event)
    }
}

Item {
    visible: !pane.popup.eventEditorOpen
    width: parent.width
    height: Math.max(headingColumn.implicitHeight, modePills.implicitHeight)
    Column {
        id: headingColumn
        anchors.left: parent.left; anchors.right: modePills.visible ? modePills.left : parent.right
        anchors.rightMargin: Style.sm
        spacing: Style.xs
        FieldLabel {
            id: agendaTitle
            width: parent.width; wrapMode: Text.Wrap
            text: (pane.popup.eventDetailsOpen ? String(pane.popup.eventDetails.calendar || "") + "  ·  " + pane.popup.dayHeading
                : pane.popup.agendaMode === "week" ? pane.popup.weekHeading
                : pane.popup.dayHeading).toUpperCase()
            color: pane.popup.secondaryText
        }
        Text {
            visible: pane.popup.agendaMode === "day" && !pane.popup.eventPanelOpen && text !== ""
            width: parent.width
            text: pane.popup.daySummary
            color: pane.popup.shell.mutedText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
        }
    }
    Row {
        id: modePills
        visible: !pane.popup.eventPanelOpen
        anchors.right: parent.right; anchors.top: parent.top
        spacing: Style.xs
        Repeater {
            model: ["day", "week"]
            Chip {
                required property var modelData
                text: String(modelData).toUpperCase()
                selected: pane.popup.agendaMode === String(modelData)
                onPicked: pane.popup.agendaMode = String(modelData)
            }
        }
    }
}

Column {
    visible: pane.popup.agendaMode === "day" && !pane.popup.eventPanelOpen
    width: parent.width; spacing: Style.sectionGap
    Rectangle {
        visible: pane.popup.dayItems.length === 0
        width: parent.width; height: emptyText.implicitHeight + Style.sectionGap * 2
        radius: pane.popup.shell.rounding
        color: "transparent"
        border.width: 1
        border.color: pane.popup.structureLine
        Text {
            id: emptyText
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.sectionGap
            wrapMode: Text.Wrap
            text: pane.popup.selectedDayAgenda.unavailable === true ? "khal is not configured" : "Nothing scheduled. Add something above."
            color: pane.popup.shell.mutedText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
    }
    Column {
        visible: pane.popup.allDayEvents.length > 0
        width: parent.width; spacing: Style.xxs
        FieldLabel { bottomPadding: Style.sm; text: "ALL DAY  ·  " + pane.popup.allDayEvents.length }
        Repeater {
            model: pane.popup.allDayEvents
            AgendaRow {
                required property var modelData
                required property int index
                event: modelData
                itemIndex: index
            }
        }
    }
    Column {
        visible: pane.popup.timedEvents.length > 0
        width: parent.width; spacing: Style.xxs
        FieldLabel { bottomPadding: Style.sm; text: "SCHEDULED" }
        Repeater {
            model: pane.popup.timedEvents
            Column {
                id: timedEntry
                required property var modelData
                required property int index
                width: parent.width; spacing: Style.xxs
                NowLine { visible: timedEntry.index === pane.popup.nowLineIndex }
                AgendaRow { event: timedEntry.modelData; itemIndex: pane.popup.allDayEvents.length + timedEntry.index }
            }
        }
        NowLine { visible: pane.popup.nowLineIndex === pane.popup.timedEvents.length }
    }
}

Column {
    visible: pane.popup.agendaMode === "week" && !pane.popup.eventPanelOpen
    width: parent.width; spacing: Style.xs

    Item {
        width: parent.width; height: Style.px(22)
        ClockNavButton { popup: pane.popup;
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            glyph: "‹"; size: Style.display; onActivated: pane.popup.moveDay(-7)
        }
        ClockNavButton { popup: pane.popup;
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            glyph: "›"; size: Style.display; onActivated: pane.popup.moveDay(7)
        }
        Text {
            anchors.centerIn: parent
            visible: pane.popup.selectedWeekDates.indexOf(CalendarMath.isoDay(pane.popup.today)) < 0
            text: "\u{f0954}  this week"
            color: mouse.containsMouse ? pane.popup.shell.role("hvr_fg", pane.popup.shell.foreground) : pane.popup.shell.mutedText
            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
            MouseArea {
                id: mouse
                anchors.fill: parent; anchors.margins: -6
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: pane.popup.goToToday()
            }
        }
    }

    Repeater {
        model: pane.popup.selectedWeekDates
        Rectangle {
            id: dayCard
            required property string modelData
            readonly property var events: pane.popup.eventsOnDate(dayCard.modelData)
            readonly property date date: CalendarMath.fromIsoDay(dayCard.modelData)
            readonly property bool isToday: dayCard.modelData === CalendarMath.isoDay(pane.popup.today)
            readonly property bool isSelected: dayCard.modelData === CalendarMath.isoDay(pane.popup.selectedDate)
            readonly property bool isWeekend: CalendarMath.isWeekend(dayCard.modelData)
            property Item hoveredChip: null

            width: parent.width
            height: cardRow.implicitHeight + Style.px(14)
            radius: pane.popup.shell.rounding
            color: cardHover.hovered && !dayCard.hoveredChip ? pane.popup.shell.hoverFill()
                : dayCard.isSelected ? pane.popup.shell.selectedFill()
                : pane.popup.shell.alpha(pane.popup.shell.foreground, dayCard.isWeekend ? .025 : .04)
            Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
            HoverHandler { id: cardHover }

            MouseArea {
                z: -1
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    pane.popup.showDay(dayCard.date)
                    pane.popup.agendaMode = "day"
                }
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
                        color: pane.popup.shell.alpha(pane.popup.shell.foreground, dayCard.isWeekend ? .35 : .5)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                        font.letterSpacing: 1; font.bold: dayCard.isToday
                    }
                    Text {
                        text: dayCard.date.getDate() + " · " + Qt.formatDate(dayCard.date, "MMM")
                        color: dayCard.isToday ? pane.popup.shell.accent : pane.popup.shell.foreground
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.body
                        font.bold: dayCard.isToday || dayCard.isSelected
                    }
                    Text {
                        visible: text !== ""
                        text: pane.popup.relativeDayLabel(dayCard.modelData)
                        color: dayCard.isToday
                            ? pane.popup.shell.role("act_br", pane.popup.shell.accent)
                            : pane.popup.shell.alpha(pane.popup.shell.foreground, .35)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                        font.italic: true
                    }
                }

                Rectangle {
                    width: 1; height: cardRow.implicitHeight
                    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .1)
                }

                Column {
                    id: chipColumn
                    width: cardRow.width - dateRail.width - 1 - cardRow.spacing * 2
                    spacing: Style.xs
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: dayCard.events.slice(0, pane.maxChips)
                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property color tint: pane.popup.eventChipColor(chip.modelData)
                            width: chipColumn.width; height: Style.px(22)
                            radius: pane.popup.shell.rounding
                            color: chipHover.hovered ? pane.popup.shell.hoverFill() : "transparent"
                            Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: chipHover
                                onHoveredChanged: {
                                    if (hovered) dayCard.hoveredChip = chip
                                    else if (dayCard.hoveredChip === chip) dayCard.hoveredChip = null
                                }
                            }
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Style.controlPaddingX
                                anchors.rightMargin: Style.controlPaddingX
                                spacing: Style.xs
                                Dot { anchors.verticalCenter: parent.verticalCenter; color: chip.tint }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Style.px(38)
                                    text: chip.modelData.allDay ? "all" : chip.modelData.start
                                    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .55)
                                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Style.px(38) - Style.md - Style.xs * 2
                                    text: chip.modelData.title; elide: Text.ElideRight
                                    color: pane.popup.shell.foreground
                                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pane.popup.selectedDate = dayCard.date
                                    pane.popup.openEvent(chip.modelData)
                                }
                            }
                        }
                    }
                    Text {
                        visible: dayCard.events.length > pane.maxChips
                        width: chipColumn.width
                        text: "+" + (dayCard.events.length - pane.maxChips) + " more"
                        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .4)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                        font.italic: true
                    }
                    Text {
                        visible: dayCard.events.length === 0
                        width: chipColumn.width
                        text: "— Free —"
                        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .28)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                        font.italic: true
                    }
                }
            }
        }
    }
}

Loader {
    width: parent.width
    active: pane.popup.eventDetailsOpen
    visible: active
    sourceComponent: Component {
        Rectangle {
            width: parent ? parent.width : 0
            implicitHeight: Math.max(detailColumn.implicitHeight + Style.controlPaddingX * 2,
                pane.calendarHeight - agendaTitle.implicitHeight - agendaContent.spacing)
            radius: pane.popup.shell.rounding
            color: "transparent"
            border.width: 1
            border.color: pane.popup.structureLine
            focus: true
            Keys.onEscapePressed: pane.popup.closeEventDetails()

            Column {
                id: detailColumn
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: Style.controlPaddingX
                spacing: Style.sm

                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: String(pane.popup.eventDetails.title || "")
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.display
                    font.bold: true
                }
                Row {
                    spacing: Style.sm
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.px(6); height: Style.px(6); radius: 3
                        color: pane.popup.calendarColor(String(pane.popup.eventDetails.calendar || ""),
                            pane.popup.shell.role("act_br", pane.popup.shell.accent))
                    }
                    Text {
                        text: String(pane.popup.eventDetails.calendar || "") + "  ·  read-only"
                        color: pane.popup.shell.mutedText
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }

                Item { width: 1; height: Style.xs }

                FieldLabel { text: "WHEN" }
                Text {
                    width: parent.width; text: pane.popup.eventDetailsTime()
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }

                FieldLabel { visible: repeatValue.visible; text: "REPEATS" }
                Text {
                    id: repeatValue
                    visible: text !== ""
                    width: parent.width; text: String(pane.popup.eventDetails.repeat || "")
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }

                FieldLabel { visible: locationValue.visible; text: "WHERE" }
                Text {
                    id: locationValue
                    visible: text !== ""
                    width: parent.width; wrapMode: Text.Wrap
                    text: String(pane.popup.eventDetails.location || "")
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }

                FieldLabel { visible: notesValue.visible; text: "NOTES" }
                Text {
                    id: notesValue
                    visible: text !== ""
                    width: parent.width; wrapMode: Text.Wrap
                    text: String(pane.popup.eventDetails.description || "")
                    color: pane.popup.secondaryText
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
            }

            FormButton {
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: Style.controlPaddingX
                width: pane.popup.choiceColumn; text: "Close"
                onActivated: pane.popup.closeEventDetails()
            }
            Component.onCompleted: forceActiveFocus()
        }
    }
}

Loader {
    width: parent.width
    active: pane.popup.eventEditorOpen
    visible: active
    sourceComponent: Component {
        Column {
            id: form
            width: parent ? parent.width : 0
            spacing: Style.lg
            Keys.onEscapePressed: pane.popup.closeEventPanels()

            Item {
                width: parent.width; height: Math.max(formTitle.implicitHeight, formButtons.height)
                FieldLabel {
                    id: formTitle
                    anchors.left: parent.left; anchors.right: formButtons.left
                    anchors.rightMargin: Style.lg; anchors.verticalCenter: parent.verticalCenter
                    text: pane.popup.editedEventUid !== "" ? "EDIT EVENT" : "NEW EVENT"
                    elide: Text.ElideRight
                }
                Row {
                    id: formButtons
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.md
                    FormButton { text: "Cancel"; onActivated: pane.popup.closeEventPanels() }
                    FormButton { text: pane.popup.editedEventUid !== "" ? "Save" : "Create"; primary: true; onActivated: pane.popup.saveRequested() }
                }
            }
            Text {
                visible: text !== ""
                width: parent.width; wrapMode: Text.Wrap
                text: pane.popup.eventEditorError
                color: pane.popup.shell.role("error", pane.popup.shell.foreground)
                font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
            }

            FormField {
                id: titleField
                width: parent.width
                placeholderText: "Add title"
                Keys.onReturnPressed: pane.popup.saveRequested()
                Keys.onEnterPressed: pane.popup.saveRequested()
            }

            FieldRow {
                id: startsRow
                label: "STARTS"
                ClockDatePicker {
                    shell: pane.popup.shell; weekStart: pane.popup.weekStart
                    width: pane.popup.draft.allDay ? startsRow.slotWidth : startsRow.halfSlot
                    value: pane.popup.draft.startDate || ""
                    onPicked: day => pane.popup.setDraftStartDate(day)
                }
                PopupSelect {
                    visible: !pane.popup.draft.allDay
                    width: startsRow.halfSlot
                    shell: pane.popup.shell
                    choices: pane.popup.startTimeChoices
                    selectedIndex: Math.max(0, choices.findIndex(choice => choice.value === pane.popup.draft.startTime))
                    onActivated: index => pane.popup.setDraftStartTime(choices[index].value)
                }
            }
            FieldRow {
                id: endsRow
                label: "ENDS"
                ClockDatePicker {
                    shell: pane.popup.shell; weekStart: pane.popup.weekStart
                    width: pane.popup.draft.allDay ? endsRow.slotWidth : endsRow.halfSlot
                    value: pane.popup.draft.endDate || ""
                    onPicked: day => pane.popup.setDraftEndDate(day)
                }
                PopupSelect {
                    visible: !pane.popup.draft.allDay
                    width: endsRow.halfSlot
                    shell: pane.popup.shell
                    choices: pane.popup.endTimeChoices
                    selectedIndex: Math.max(0, choices.findIndex(choice => choice.value === pane.popup.draft.endTime))
                    onActivated: index => pane.popup.updateDraft({ endTime: choices[index].value })
                }
            }
            FieldRow {
                label: "ALL DAY"
                ToggleSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    shell: pane.popup.shell
                    checked: pane.popup.draft.allDay === true
                    onToggled: pane.popup.updateDraft({ allDay: !pane.popup.draft.allDay })
                }
            }
            FieldRow {
                id: repeatRow
                label: "REPEAT"
                PopupSelect {
                    width: repeatRow.slotWidth
                    shell: pane.popup.shell
                    choices: pane.popup.repeatChoices
                    selectedIndex: Math.max(0, choices.findIndex(choice => choice.value === (pane.popup.draft.repeat || "")))
                    onActivated: index => pane.popup.updateDraft({ repeat: choices[index].value })
                }
            }
            FieldRow {
                id: alertRow
                label: "ALERT"
                PopupSelect {
                    width: alertRow.slotWidth
                    shell: pane.popup.shell
                    choices: pane.popup.draftAlarmChoices
                    selectedIndex: Math.max(0, choices.findIndex(choice => choice.value === pane.popup.effectiveAlarm))
                    onActivated: index => pane.popup.updateDraft({ alarm: choices[index].value })
                }
            }

            FieldRow {
                id: locationRow
                z: 1
                label: "LOCATION"
                FormField {
                    id: locationField; width: locationRow.slotWidth
                    placeholderText: "Search a place or type an address"

                    readonly property bool listOpen: activeFocus && !pane.popup.locationSuggestionsDismissed
                        && pane.popup.locationSuggestions.length > 0
                    function accept(value) {
                        locationField.text = String(value)
                        locationField.cursorPosition = locationField.text.length
                    }
                    onTextChanged: if (locationField.activeFocus) pane.popup.locationQuery = text
                    onActiveFocusChanged: if (!activeFocus) pane.popup.locationSuggestionsDismissed = true

                    Keys.onReturnPressed: event => {
                        if (locationField.listOpen) {
                            locationField.accept(pane.popup.locationSuggestions[pane.popup.locationSelectionIndex])
                            event.accepted = true
                            return
                        }
                        descriptionField.forceActiveFocus()
                    }
                    Keys.onEnterPressed: event => {
                        if (locationField.listOpen) {
                            locationField.accept(pane.popup.locationSuggestions[pane.popup.locationSelectionIndex])
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
                        locationField.accept(pane.popup.locationSuggestions[pane.popup.locationSelectionIndex])
                        event.accepted = true
                    }
                    Keys.onDownPressed: event => {
                        if (!locationField.listOpen) {
                            event.accepted = false
                            return
                        }
                        pane.popup.locationSelectionIndex = Math.min(pane.popup.locationSelectionIndex + 1,
                            pane.popup.locationSuggestions.length - 1)
                        event.accepted = true
                    }
                    Keys.onUpPressed: event => {
                        if (!locationField.listOpen) {
                            event.accepted = false
                            return
                        }
                        pane.popup.locationSelectionIndex = Math.max(pane.popup.locationSelectionIndex - 1, 0)
                        event.accepted = true
                    }
                    Keys.onEscapePressed: event => {
                        if (locationField.listOpen) {
                            pane.popup.locationSuggestionsDismissed = true
                            event.accepted = true
                            return
                        }
                        pane.popup.closeEventPanels()
                    }

                    Rectangle {
                        visible: locationField.listOpen
                        y: locationField.height + 2
                        width: locationField.width
                        height: suggestionColumn.implicitHeight + 2
                        radius: pane.popup.shell.rounding
                        color: pane.popup.shell.role("bg", pane.popup.shell.background)
                        border.width: 1
                        border.color: pane.popup.structureLine
                        Column {
                            id: suggestionColumn
                            y: 1; width: parent.width
                            Repeater {
                                model: pane.popup.locationSuggestions
                                Rectangle {
                                    id: suggestionRow
                                    required property var modelData
                                    required property int index
                                    width: suggestionColumn.width; height: Style.px(20)
                                    color: hoverArea.containsMouse ? pane.popup.shell.hoverFill()
                                        : suggestionRow.index === pane.popup.locationSelectionIndex ? pane.popup.shell.selectedFill() : "transparent"
                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: Style.controlPaddingX
                                        anchors.rightMargin: Style.controlPaddingX
                                        verticalAlignment: Text.AlignVCenter
                                        text: String(suggestionRow.modelData); elide: Text.ElideRight
                                        color: pane.popup.shell.foreground
                                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
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

            }

            FieldRow {
                id: notesRow
                label: "NOTES"
                FormArea {
                    id: descriptionField; width: notesRow.slotWidth; lines: 2
                }
            }

            FieldRow {
                id: calendarRow
                label: "CALENDAR"
                PopupSelect {
                    visible: pane.popup.writableCalendars.length > 1
                    width: calendarRow.slotWidth
                    shell: pane.popup.shell
                    choices: pane.popup.writableCalendars.map(name => ({ label: name, value: name }))
                    selectedIndex: Math.max(0, pane.popup.writableCalendars.indexOf(pane.popup.draft.calendar))
                    onActivated: index => pane.popup.updateDraft({ calendar: choices[index].value })
                }
                Row {
                    visible: pane.popup.writableCalendars.length <= 1
                    height: Style.controlHeight; spacing: Style.md
                    Dot {
                        anchors.verticalCenter: parent.verticalCenter
                        color: pane.popup.calendarColor(String(pane.popup.draft.calendar || ""), pane.popup.shell.role("act_br", pane.popup.shell.accent))
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(pane.popup.draft.calendar || "")
                        color: pane.popup.shell.foreground
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                }
            }

            Text {
                width: parent.width
                textFormat: Text.StyledText
                text: Commons.Util.keyHintMarkup("↑↓/Tab Suggestions  Ctrl+Enter Save  Esc Cancel", pane.popup.shell.alpha(pane.popup.shell.foreground, .3))
                color: pane.popup.shell.accent
                font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                horizontalAlignment: Text.AlignHCenter
            }

            Connections {
                target: pane.popup
                function onSaveRequested() { pane.popup.saveDraft(titleField.text, locationField.text, descriptionField.text) }
            }
            Component.onCompleted: {
                titleField.text = pane.popup.draft.title || ""
                locationField.text = pane.popup.draft.location || ""
                descriptionField.text = pane.popup.draft.description || ""
                titleField.forceActiveFocus()
            }
        }
    }
}

    }
}

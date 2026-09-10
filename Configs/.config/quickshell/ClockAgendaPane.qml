pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "CalendarMath.js" as CalendarMath

Item {
    id: pane
    required property var popup
    required property real calendarHeight
    width: pane.popup.agendaVisible ? pane.popup.agendaWidth : 0
    height: agendaContent.implicitHeight
    visible: pane.popup.agendaVisible
    clip: true

    component FieldLabel: Text {
        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .45)
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
        color: selected ? pane.popup.shell.alpha(pane.popup.shell.role("act_br", pane.popup.shell.accent), .35)
            : chipArea.containsMouse ? pane.popup.shell.alpha(pane.popup.shell.foreground, .1) : "transparent"
        border.width: 1
        border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, selected ? .4 : .16)
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Text {
            id: chipText
            anchors.centerIn: parent
            color: pane.popup.shell.alpha(pane.popup.shell.foreground, parent.selected ? 1 : .6)
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
        background: Rectangle {
            radius: pane.popup.shell.rounding
            color: pane.popup.shell.alpha(pane.popup.shell.foreground, .06)
            border.width: 1
            border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, area.activeFocus ? .45 : .18)
        }
        TextArea {
            id: area
            wrapMode: TextArea.Wrap
            leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
            topPadding: Style.controlPaddingY; bottomPadding: Style.controlPaddingY
            color: pane.popup.shell.foreground
            placeholderTextColor: pane.popup.shell.alpha(pane.popup.shell.foreground, .28)
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
        opacity: enabled ? 1 : .4
        color: primary
            ? pane.popup.shell.alpha(pane.popup.shell.role("act_br", pane.popup.shell.accent), buttonArea.containsMouse ? .5 : .3)
            : buttonArea.containsMouse ? pane.popup.shell.alpha(pane.popup.shell.foreground, .12) : "transparent"
        border.width: 1
        border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, primary ? .4 : .22)
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

    Column {
    id: agendaContent
    anchors.right: parent.right
    width: pane.popup.agendaWidth
    spacing: Style.px(10)

Item {
    width: parent.width
    height: Math.max(agendaTitle.implicitHeight, modePills.implicitHeight)
    Text {
        id: agendaTitle
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - modePills.width - Style.sm
        elide: Text.ElideRight
        readonly property string dayLabel: Qt.formatDate(pane.popup.selectedDate, "dddd d MMMM").toUpperCase()
        text: pane.popup.editedEventUid !== "" ? "EDITING \u2014 " + dayLabel
            : pane.popup.eventDetailsOpen ? String(pane.popup.eventDetails.calendar || "").toUpperCase() + " \u2014 " + dayLabel
            : pane.popup.agendaMode === "week" ? pane.popup.weekHeading.toUpperCase()
            : dayLabel
        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .55)
        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
        font.letterSpacing: 1; font.bold: true
    }
    Row {
        id: modePills
        visible: !pane.popup.eventPanelOpen
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
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
Text {
    visible: pane.popup.agendaMode === "day" && pane.popup.selectedDayEvents.length === 0 && !pane.popup.eventPanelOpen
    width: parent.width
    text: pane.popup.selectedDayAgenda.unavailable === true ? "khal is not configured" : "Nothing scheduled"
    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .35)
    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
}
Column {
    visible: pane.popup.agendaMode === "day" && !pane.popup.eventPanelOpen
    width: parent.width; spacing: 3
    Repeater {
        model: pane.popup.selectedDayEvents
        Item {
            id: eventItem
            required property var modelData
            width: parent.width
            height: eventRow.implicitHeight

            HoverHandler { id: eventHover }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: pane.popup.shell.rounding
                color: eventHover.hovered
                    ? pane.popup.shell.alpha(pane.popup.shell.foreground, .08) : "transparent"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: pane.popup.openEvent(eventItem.modelData)
            }

            Row {
            id: eventRow
            width: parent.width; spacing: Style.sm
            Text {
                width: Style.px(40)
                text: eventItem.modelData.allDay ? "all" : eventItem.modelData.start
                color: pane.popup.eventColor(eventItem.modelData)
                font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Column {
                width: parent.width - 40 - Style.sm - 22; spacing: 0
                Text {
                    width: parent.width; text: eventItem.modelData.title; elide: Text.ElideRight
                    color: pane.popup.shell.foreground
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Row {
                    width: parent.width; spacing: Style.xs
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: [pane.popup.secondaryCalendarName(eventItem.modelData),
                            eventItem.modelData.location,
                            eventItem.modelData.description].filter(part => !!part).join("  ·  ")
                        elide: Text.ElideRight
                        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .4)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: eventHover.hovered && !pane.popup.eventIsReadOnly(eventItem.modelData)
                width: Style.px(20); height: Style.px(20); radius: pane.popup.shell.rounding
                color: binArea.containsMouse
                    ? pane.popup.shell.alpha(pane.popup.shell.role("error", pane.popup.shell.foreground), .25) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0a7a}"
                    color: binArea.containsMouse ? pane.popup.shell.role("error", pane.popup.shell.foreground)
                        : pane.popup.shell.alpha(pane.popup.shell.foreground, .6)
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                MouseArea {
                    id: binArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: pane.popup.deleteEvent(eventItem.modelData.uid)
                }
            }
        }
    }
}

Column {
    visible: pane.popup.agendaMode === "week" && !pane.popup.eventPanelOpen
    width: parent.width; spacing: Style.xs

    Item {
        width: parent.width; height: Style.px(22)
        ClockNavButton { popup: pane.popup;
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            glyph: "\u2039"; size: Style.display; onActivated: pane.popup.moveDay(-7)
        }
        ClockNavButton { popup: pane.popup;
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            glyph: "\u203a"; size: Style.display; onActivated: pane.popup.moveDay(7)
        }
        Text {
            anchors.centerIn: parent
            visible: pane.popup.selectedWeekDates.indexOf(CalendarMath.isoDay(pane.popup.today)) < 0
            text: "\u{f0954}  this week"
            color: pane.popup.shell.alpha(pane.popup.shell.foreground, mouse.containsMouse ? .9 : .45)
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

            width: parent.width
            height: cardRow.implicitHeight + Style.px(14)
            radius: pane.popup.shell.rounding
            color: dayCard.isSelected
                ? pane.popup.shell.alpha(pane.popup.shell.role("act_bg", pane.popup.shell.accent), .3)
                : dayCard.isToday ? pane.popup.shell.alpha(pane.popup.shell.foreground, .07)
                : dayCard.isWeekend ? pane.popup.shell.alpha(pane.popup.shell.foreground, .025)
                : pane.popup.shell.alpha(pane.popup.shell.foreground, .04)
            border.width: dayCard.isToday && !dayCard.isSelected ? 1 : 0
            border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, .2)

            Rectangle {
                visible: dayCard.isToday || dayCard.isSelected
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: Style.px(3); height: parent.height - Style.px(10); radius: 1
                color: pane.popup.shell.role("act_br", pane.popup.shell.accent)
            }

            MouseArea {
                z: -1
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: pane.popup.selectedDate = dayCard.date
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
                        color: pane.popup.shell.foreground
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
                        model: dayCard.events.slice(0, 3)
                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property color tint: pane.popup.eventChipColor(chip.modelData)
                            width: chipColumn.width; height: Style.px(22)
                            radius: pane.popup.shell.rounding
                            color: pane.popup.shell.alpha(chip.tint, .13)
                            border.width: 1
                            border.color: pane.popup.shell.alpha(chip.tint, .24)
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
                                    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .55)
                                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Style.px(38) - 2 - Style.xs * 2
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
                        visible: dayCard.events.length > 3
                        width: chipColumn.width
                        text: "+" + (dayCard.events.length - 3) + " more"
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
            border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, .2)
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
                        color: pane.popup.shell.alpha(pane.popup.shell.foreground, .45)
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
                    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .75)
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
        Rectangle {
            width: parent ? parent.width : 0
            implicitHeight: Math.max(formColumn.implicitHeight + Style.controlPaddingX * 2,
                pane.calendarHeight - agendaTitle.implicitHeight - agendaContent.spacing)
            radius: pane.popup.shell.rounding
            color: "transparent"
            border.width: 1
            border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, .2)

            Column {
                id: formColumn
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: Style.controlPaddingX
                spacing: Style.sm

                FormField {
                    id: titleField
                    width: parent.width; text: pane.popup.draftValues.title || ""
                    placeholderText: "What is happening"
                    Keys.onReturnPressed: startField.forceActiveFocus()
                    Keys.onEnterPressed: startField.forceActiveFocus()
                }

                Item { width: 1; height: Style.xs }

                Item {
                    width: parent.width; height: Math.max(allDayLabel.implicitHeight, allDaySwitch.height)
                    FieldLabel { id: allDayLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "ALL DAY" }
                    ToggleSwitch { id: allDaySwitch; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; shell: pane.popup.shell; checked: pane.popup.draftAllDay; onToggled: pane.popup.draftAllDay = !pane.popup.draftAllDay }
                }

                Item { width: 1; height: Style.xs }

                Row {
                    width: parent.width; spacing: Style.lg
                    Column { id: startFields; width: pane.popup.choiceColumn - Style.controlPaddingX * 2; spacing: Style.sm
                        opacity: pane.popup.draftAllDay ? .35 : 1
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        FieldLabel { text: "START" }
                        FormField {
                            id: startField; width: parent.width; enabled: !pane.popup.draftAllDay
                            text: pane.popup.draftValues.start || ""; placeholderText: "09:00"; inputMask: "99:99"
                            Keys.onReturnPressed: endField.forceActiveFocus(); Keys.onEnterPressed: endField.forceActiveFocus()
                        }
                    }
                    Item { width: Style.xl; height: startFields.implicitHeight; opacity: startFields.opacity
                        Text { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Style.px(24)
                            text: "→"; color: pane.popup.shell.alpha(pane.popup.shell.foreground, .35)
                            font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Column { id: endFields; width: startFields.width; spacing: Style.sm; opacity: startFields.opacity
                        FieldLabel { text: "END" }
                        FormField {
                            id: endField; width: parent.width; enabled: !pane.popup.draftAllDay
                            text: pane.popup.draftValues.end || ""; placeholderText: "optional"; inputMask: "99:99"
                            Keys.onReturnPressed: endDayField.forceActiveFocus(); Keys.onEnterPressed: endDayField.forceActiveFocus()
                        }
                    }
                    Item { width: parent.width - startFields.width * 2 - untilFields.width - Style.xl - parent.spacing * 4; height: 1 }
                    Column { id: untilFields; width: pane.popup.choiceColumn + Style.controlPaddingX * 2; spacing: Style.sm
                        FieldLabel { text: "UNTIL" }
                        FormField {
                            id: endDayField; width: parent.width
                            text: pane.popup.draftValues.endDay || ""; placeholderText: CalendarMath.isoDay(pane.popup.selectedDate); inputMask: "9999-99-99"
                            Keys.onReturnPressed: locationField.forceActiveFocus(); Keys.onEnterPressed: locationField.forceActiveFocus()
                        }
                    }
                }

                Item { width: 1; height: Style.xs }

                FormField {
                    id: locationField; width: parent.width; z: 10
                    text: pane.popup.draftValues.location || ""; placeholderText: "Location (optional)"

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
                        border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, .25)
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
                                    color: suggestionRow.index === pane.popup.locationSelectionIndex
                                        ? pane.popup.shell.alpha(pane.popup.shell.role("act_bg", pane.popup.shell.accent), .35)
                                        : hoverArea.containsMouse
                                        ? pane.popup.shell.alpha(pane.popup.shell.foreground, .08) : "transparent"
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

                FormArea {
                    id: descriptionField; width: parent.width; lines: 2
                    text: pane.popup.draftValues.description || ""; placeholderText: "Description (optional)"
                }

                Item { width: 1; height: Style.xs }

                Row {
                    id: calendarRow
                    visible: pane.popup.writableCalendars.length > 1
                    width: parent.width; height: Style.px(22); spacing: Style.sm
                    FieldLabel {
                        id: calendarLabel
                        width: pane.popup.choiceColumn - Style.controlPaddingX * 2
                        height: parent.height; text: "CALENDAR"
                        verticalAlignment: Text.AlignVCenter
                    }
                    Repeater {
                        model: pane.popup.writableCalendars
                        Chip {
                            required property var modelData
                            width: (calendarRow.width - calendarLabel.width
                                - calendarRow.spacing * pane.popup.writableCalendars.length)
                                / pane.popup.writableCalendars.length
                            text: String(modelData)
                            selected: pane.popup.draftCalendar === String(modelData)
                            onPicked: pane.popup.draftCalendar = String(modelData)
                        }
                    }
                }
                Row {
                    id: alarmRow
                    width: parent.width; height: Style.px(22); spacing: Style.sm
                    FieldLabel { id: alertLabel; width: pane.popup.choiceColumn - Style.controlPaddingX * 2; height: parent.height; text: "ALERT"; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: pane.popup.alarmChoices
                        Chip {
                            required property var modelData
                            width: (alarmRow.width - alertLabel.width - alarmRow.spacing * pane.popup.alarmChoices.length) / pane.popup.alarmChoices.length
                            text: modelData.label; selected: pane.popup.draftAlarm === modelData.value
                            onPicked: pane.popup.draftAlarm = modelData.value
                        }
                    }
                }
                Row {
                    id: repeatRow
                    width: parent.width; height: Style.px(22); spacing: Style.sm
                    FieldLabel { id: repeatLabel; width: alertLabel.width; height: parent.height; text: "REPEAT"; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: pane.popup.repeatChoices
                        Chip {
                            required property var modelData
                            width: (repeatRow.width - repeatLabel.width - repeatRow.spacing * pane.popup.repeatChoices.length) / pane.popup.repeatChoices.length
                            text: modelData.label; selected: pane.popup.draftRepeat === modelData.value
                            onPicked: pane.popup.draftRepeat = modelData.value
                        }
                    }
                }

                Item { width: 1; height: Style.xs }

                Item {
                    width: parent.width; height: Style.px(24)
                    Text {
                        visible: pane.popup.eventEditorError !== ""
                        anchors.left: parent.left; anchors.right: formButtons.left; anchors.rightMargin: Style.sm
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f002a}  " + pane.popup.eventEditorError; elide: Text.ElideRight
                        color: pane.popup.shell.role("error", pane.popup.shell.foreground)
                        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                    Row {
                        id: formButtons; anchors.right: parent.right; spacing: Style.lg
                        FormButton { width: pane.popup.choiceColumn; text: "Cancel"; onActivated: pane.popup.closeEventPanels() }
                        FormButton {
                            width: pane.popup.choiceColumn; text: pane.popup.editedEventUid !== "" ? "Save" : "Add"; primary: true
                            onActivated: pane.popup.saveRequested()
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "↑↓ Tab  suggestions     Ctrl+Enter  save     Esc  cancel"
                    color: pane.popup.shell.alpha(pane.popup.shell.foreground, .3)
                    font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.caption
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Connections {
                target: pane.popup
                function onSaveRequested() {
                    pane.popup.validateAndSaveEvent({
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
    visible: pane.popup.agendaMode === "day" && !pane.popup.eventPanelOpen
    radius: pane.popup.shell.rounding
    color: addArea.containsMouse ? pane.popup.shell.alpha(pane.popup.shell.foreground, .1) : "transparent"
    border.width: addArea.containsMouse ? 1 : 0
    border.color: pane.popup.shell.alpha(pane.popup.shell.foreground, .25)
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    Text {
        anchors.centerIn: parent
        text: "\u{f0415}  Add event"
        color: pane.popup.shell.alpha(pane.popup.shell.foreground, addArea.containsMouse ? .9 : .45)
        font.family: pane.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
    }
    MouseArea {
        id: addArea
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: pane.popup.openNewEventEditor()
    }
}
    }

    }

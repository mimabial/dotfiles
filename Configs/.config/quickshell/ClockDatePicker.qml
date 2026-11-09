pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "CalendarMath.js" as CalendarMath

Item {
    id: root
    required property var shell
    property string value: ""
    property int weekStart: 1
    property date viewMonth: new Date()
    readonly property int gridCells: 6 * 7
    readonly property int cellWidth: Style.px(28)
    readonly property int cellHeight: Style.px(24)
    signal picked(string day)
    implicitHeight: Style.controlHeight

    readonly property var days: {
        const first = new Date(root.viewMonth.getFullYear(), root.viewMonth.getMonth(), 1)
        const lead = (first.getDay() - root.weekStart + 7) % 7
        const out = []
        for (let index = 0; index < root.gridCells; index++)
            out.push(new Date(first.getFullYear(), first.getMonth(), index - lead + 1))
        return out
    }
    function openPicker() {
        const day = root.value !== "" ? CalendarMath.fromIsoDay(root.value) : new Date()
        root.viewMonth = new Date(day.getFullYear(), day.getMonth(), 1)
        popup.open()
    }
    function stepMonth(delta) { root.viewMonth = new Date(root.viewMonth.getFullYear(), root.viewMonth.getMonth() + delta, 1) }

    component MonthArrow: Text {
        property int delta: 0
        color: arrowArea.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.foreground
        font.family: root.shell.fontFamily; font.pixelSize: Style.body
        MouseArea {
            id: arrowArea
            anchors.fill: parent; anchors.margins: -Style.sm
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.stepMonth(parent.delta)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.shell.rounding
        color: triggerArea.containsMouse ? root.shell.hoverFill() : popup.visible ? root.shell.selectedFill()
            : root.shell.alpha(root.shell.foreground, Style.fieldFillAlpha)
        border.width: 1
        border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
        Behavior on color { ColorAnimation { duration: Style.hoverDuration } }
        Text {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: root.value !== "" ? Qt.formatDate(CalendarMath.fromIsoDay(root.value), "ddd d MMM yyyy") : ""
            elide: Text.ElideRight
            color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: triggerArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: popup.visible ? popup.close() : root.openPicker()
        }
    }

    Popup {
        id: popup
        y: root.height + Style.xxs
        padding: Style.lg
        focus: true
        popupType: Popup.Item
        background: Rectangle {
            radius: root.shell.rounding
            color: root.shell.alpha(Style.popupTinted(root.shell.role("bg", root.shell.background)), .98)
            border.width: 1; border.color: Style.popupBorder(root.shell.role("alt_br", root.shell.foreground), .45)
        }
        contentItem: Column {
            spacing: Style.sm
            Item {
                width: dayGrid.width; height: monthLabel.implicitHeight
                MonthArrow { anchors.left: parent.left; text: "‹"; delta: -1 }
                Text {
                    id: monthLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.viewMonth, "MMMM yyyy")
                    color: root.shell.foreground
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                }
                MonthArrow { anchors.right: parent.right; text: "›"; delta: 1 }
            }
            Grid {
                id: dayGrid
                columns: 7; spacing: Style.xxs
                Repeater {
                    model: 7
                    Text {
                        required property int index
                        width: root.cellWidth
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((root.weekStart + index) % 7, Locale.NarrowFormat)
                        color: root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
                Repeater {
                    model: root.days
                    Rectangle {
                        id: dayCell
                        required property date modelData
                        readonly property string iso: CalendarMath.isoDay(dayCell.modelData)
                        readonly property bool chosen: dayCell.iso === root.value
                        readonly property bool today: CalendarMath.sameDay(dayCell.modelData, new Date())
                        readonly property bool inMonth: dayCell.modelData.getMonth() === root.viewMonth.getMonth()
                        width: root.cellWidth; height: root.cellHeight
                        radius: root.shell.rounding
                        color: dayHover.hovered ? root.shell.hoverFill() : dayCell.chosen ? root.shell.selectedFill() : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: dayCell.modelData.getDate()
                            color: dayCell.today ? root.shell.accent : dayCell.inMonth ? root.shell.foreground : root.shell.faintText
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            font.bold: dayCell.chosen || dayCell.today
                        }
                        HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                root.picked(dayCell.iso)
                                popup.close()
                            }
                        }
                    }
                }
            }
        }
    }
}

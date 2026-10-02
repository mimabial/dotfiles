pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../CalendarMath.js" as CalendarMath
import ".."

ClockButton {
    id: root
    property var notifications: []
    readonly property date today: shell.clock.date
    readonly property date firstShown: CalendarMath.startOfWeek(new Date(today.getFullYear(), today.getMonth(), 1), Qt.locale().firstDayOfWeek)
    readonly property int weeks: Math.ceil((Math.round((new Date(today.getFullYear(), today.getMonth() + 1, 0) - firstShown) / 86400000) + 1) / 7)
    readonly property color dim: shell.alpha(shell.foreground, .45)
    popupName: "notification-center"
    function archive(args) { shell.run(["hyprshell", "notify/archive"].concat(args), () => history.running = true) }
    NotificationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; popupName: "notification-center"; settings: "Notification"; settingsPopup: "notifications"
        onOpenChanged: if (open) history.running = true
        Rectangle {
            id: calendar
            readonly property bool navigable: true
            property bool cursored: false
            function activateKeyboard() { root.shell.togglePopup("clock") }
            width: parent.width; height: month.implicitHeight + Style.md * 2; radius: root.shell.rounding
            color: calendarHover.hovered || cursored ? root.shell.hoverFill() : "transparent"
            HoverHandler { id: calendarHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: calendar.activateKeyboard() }
            Column {
                id: month
                anchors.fill: parent; anchors.margins: Style.md
                Text { text: Qt.formatDate(root.today, "MMMM yyyy") + "  ›"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true }
                Grid {
                    width: parent.width; columns: 7
                    Repeater {
                        model: 7 * (root.weeks + 1)
                        Text {
                            required property int index
                            readonly property date day: new Date(root.firstShown.getFullYear(), root.firstShown.getMonth(), root.firstShown.getDate() + index - 7)
                            readonly property bool isToday: index >= 7 && CalendarMath.sameDay(day, root.today)
                            width: parent.width / 7; horizontalAlignment: Text.AlignHCenter
                            text: index < 7 ? Qt.locale().dayName((Qt.locale().firstDayOfWeek + index) % 7, Locale.NarrowFormat) : day.getDate()
                            color: isToday ? root.shell.accent : index < 7 || day.getMonth() !== root.today.getMonth() ? root.dim : root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: isToday
                        }
                    }
                }
            }
        }
        PopupSection { shell: root.shell; text: "NOTIFICATIONS"; visible: root.notifications.length > 0 }
        Repeater {
            model: root.notifications
            NotificationEntry {
                required property var modelData
                width: parent.width; shell: root.shell; showPreview: false; now: Date.now()
                app: modelData.app || ""; summary: modelData.summary || ""; body: modelData.body || ""
                iconPath: modelData.icon || ""; urgency: modelData.urgency || "NORMAL"; timestamp: Number(modelData.ts || 0)
                onClicked: { root.shell.closePopup(); root.archive([String(modelData.key)]) }
                onRemoveRequested: root.archive(["remove", String(modelData.key)])
            }
        }
        PopupRow { width: parent.width; shell: root.shell; title: "Show All Notifications…"; onClicked: root.shell.togglePopup("notifications") }
        Process {
            id: history
            command: ["hyprshell", "notify/history"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.notifications = (JSON.parse(text).entries || []).slice(0, 5) }
        }
    }
}

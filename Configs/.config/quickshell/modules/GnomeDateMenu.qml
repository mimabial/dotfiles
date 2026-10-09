pragma ComponentBehavior: Bound
import QtQuick
import ".."

ClockButton {
    id: root
    popupName: "notification-center"
    readonly property bool unread: !Notifications.report.paused && Notifications.report.unread > 0
    readonly property real indicatorSize: Style.xs
    readonly property real indicatorSpan: unread ? indicatorSize + Style.sm : 0
    readonly property real centeringPad: indicatorSpan
    property bool showWeekNumbers: false
    trailingWidth: centeringPad + indicatorSpan
    textOffsetX: centeringPad
    Rectangle {
        visible: root.unread
        width: root.indicatorSize; height: width; radius: width / 2
        color: root.shell.foreground
        anchors.verticalCenter: parent.verticalCenter
        x: root.paintedLabelBounds.x + root.paintedLabelBounds.width + Style.sm
    }
    NotificationPopup {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        popupName: "notification-center"
        calendarPane: Component { GnomeCalendar { shell: root.shell; anchorItem: root; active: root.shell.popupName === "notification-center"; showWeekNumbers: root.showWeekNumbers } }
    }
    LazyPopup { shell: root.shell; popup: "notifications"; owners: ["notifications"]; popupsAllowed: root.popupEnabled; sourceComponent: Component { NotificationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled } } }
    LazyPopup { shell: root.shell; popup: "media"; owners: ["mediaplayer", "nowplaying"]; popupsAllowed: root.popupEnabled; sourceComponent: Component { MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled } } }
}

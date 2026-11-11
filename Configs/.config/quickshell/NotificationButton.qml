import QtQuick

BarButton {
    id: root
    readonly property var filledIcons: ({ "none":"\uDB80\uDF61", "notification":"\uDB80\uDF69", "email-notification":"\uDB84\uDEF2", "chat-notification":"\uDB80\uDF66", "warning-notification":"\uDB85\uDF3A", "error-notification":"\uDB80\uDF62", "network-notification":"\uDB86\uDDCC", "battery-notification":"\uDB85\uDDA9", "update-notification":"\uDB81\uDEF1", "music-notification":"\uDB80\uDF64", "volume-notification":"\uDB86\uDDCE" })
    readonly property var outlineIcons: ({ "none":"\uDB80\uDF65", "notification":"\uDB80\uDF6A", "email-notification":"\uDB84\uDEF3", "chat-notification":"\uDB84\uDD70", "warning-notification":"\uDB85\uDF3B", "error-notification":"\uDB82\uDE04", "network-notification":"\uDB86\uDDCD", "battery-notification":"\uDB85\uDDAA", "update-notification":"\uDB84\uDD72", "music-notification":"\uDB84\uDD6C", "volume-notification":"\uDB86\uDDCF" })
    readonly property var categoriesWithBarIcon: ["email", "chat", "warning", "error", "network", "battery", "update", "music", "volume"]
    readonly property var report: Notifications.report
    readonly property var latest: (report.entries || [])[0] ?? null
    readonly property string latestCategory: String(latest?.category ?? "").toLowerCase()
    readonly property string indicatorKind: !latest ? "none"
        : categoriesWithBarIcon.includes(latestCategory) ? latestCategory + "-notification" : "notification"
    css: "notifications"
    text: (paused ? outlineIcons : filledIcons)[indicatorKind]
    readonly property string script: shell.home + "/.local/lib/hypr/notify/notifications.py"
    property bool popupEnabled: true
    property bool activeOnly: false
    property bool showBadge: true
    property bool themed: false
    symbol: themed ? paused ? "notifications-disabled" : "notification" : ""
    readonly property bool paused: report.paused === true
    readonly property int unread: report.unread || 0
    badgeText: showBadge && unread > 0 ? root.countText(unread) : ""
    visible: activeOnly ? paused : text !== ""
    onClicked: button => {
        if (button !== Qt.RightButton) {
            shell.togglePopup("notifications")
            return
        }
        shell.run([root.script, "--toggle"])
    }
    onWheeled: shell.run(["dunstctl", "history-pop"])

    NotificationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

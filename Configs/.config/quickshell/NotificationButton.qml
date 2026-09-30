import QtQuick

ScriptButton {
    id: root
    readonly property var filledIcons: ({ "none":"\uDB80\uDF61", "notification":"\uDB80\uDF69", "email-notification":"\uDB84\uDEF2", "chat-notification":"\uDB80\uDF66", "warning-notification":"\uDB85\uDF3A", "error":"\uDB80\uDF62", "error-notification":"\uDB80\uDF62", "network-notification":"\uDB86\uDDCC", "battery-notification":"\uDB85\uDDA9", "update-notification":"\uDB81\uDEF1", "music-notification":"\uDB80\uDF64", "volume-notification":"\uDB86\uDDCE" })
    readonly property var outlineIcons: ({ "none":"\uDB80\uDF65", "notification":"\uDB80\uDF6A", "email-notification":"\uDB84\uDEF3", "chat-notification":"\uDB84\uDD70", "warning-notification":"\uDB85\uDF3B", "error":"\uDB82\uDE04", "error-notification":"\uDB82\uDE04", "network-notification":"\uDB86\uDDCD", "battery-notification":"\uDB85\uDDAA", "update-notification":"\uDB84\uDD72", "music-notification":"\uDB84\uDD6C", "volume-notification":"\uDB86\uDDCF" })
    icons: paused ? outlineIcons : filledIcons
    css: "notifications"
    tooltip: ""
    // dunst signals every counter it exposes and rewrites the archive on each
    // notification, so one subscriber replaces the poll. interval is now only
    // how fast a dead helper gets respawned
    readonly property string script: shell.home + "/.local/lib/hypr/notify/notifications.py"
    command: [root.script, "--watch"]
    polling: false; streaming: true; interval: 5000
    property bool popupEnabled: true
    property bool activeOnly: false
    property bool showBadge: true
    property bool themed: false
    symbol: themed ? paused ? "notifications-disabled" : "notification" : ""
    readonly property bool paused: output.paused === true
    readonly property int unread: output.unread || 0
    badgeText: showBadge && unread > 0 ? countGlyph(unread) : ""
    visible: activeOnly ? paused : text !== ""
    // opening the panel moves the watermark, so re-read rather than waiting out
    // the poll to notice the badge should be gone
    refreshKey: shell.popupName === "notifications"
    // left opens the panel, right still toggles do-not-disturb directly
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

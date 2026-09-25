import QtQuick

ScriptButton {
    id: root
    icons: ({ "notification":"\uDB80\uDF6A", "dnd-notification":"\uDB84\uDD75", "dnd-none":"\uDB84\uDD6D", "email-notification":"\uDB83\uDD42", "chat-notification":"\uDB84\uDEC9", "warning-notification":"\uDB85\uDF3B", "error":"\uDB82\uDE04", "error-notification":"\uDB82\uDE04", "network-notification":"\uDB83\uDC8A", "battery-notification":"\uDB84\uDCCD", "update-notification":"\uDB81\uDEB0", "music-notification":"\uEC1B", "volume-notification":"\uDB81\uDFC5", "dnd":"\uDB84\uDD6D", "none":"\uDB80\uDF65" })
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
    readonly property bool paused: output.paused === true
    readonly property int unread: output.unread || 0
    badgeText: showBadge && unread > 0 ? countGlyph(unread) : ""
    active: paused
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

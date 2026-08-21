import QtQuick

ScriptButton {
    id: root
    icons: ({ "notification":"\uDB80\uDF6A", "dnd-notification":"\uDB84\uDD75", "dnd-none":"\uDB84\uDD6D", "email-notification":"\uDB83\uDD42", "chat-notification":"\uDB84\uDEC9", "warning-notification":"\uDB85\uDF3B", "error":"\uDB82\uDE04", "error-notification":"\uDB82\uDE04", "network-notification":"\uDB83\uDC8A", "battery-notification":"\uDB84\uDCCD", "update-notification":"\uDB81\uDEB0", "music-notification":"\uEC1B", "volume-notification":"\uDB81\uDFC5", "dnd":"\uDB84\uDD6D", "none":"\uDB80\uDF65" })
    css: "custom-dunst"
    command: ["hyprshell", "notifications"]; interval: 2000
    property bool popupEnabled: true
    // left opens the panel, right still toggles do-not-disturb directly
    onClicked: button => button === Qt.RightButton
        ? shell.run(["dunstctl", "set-paused", "toggle"])
        : shell.togglePopup("notifications")
    onWheeled: shell.run(["dunstctl", "history-pop"])

    NotificationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

import QtQuick

ScriptButton {
    id: root
    icons: ({ "notification":"\uDB80\uDF6A", "dnd-notification":"\uDB84\uDD75", "dnd-none":"\uDB84\uDD6D", "email-notification":"\uDB83\uDD42", "chat-notification":"\uDB84\uDEC9", "warning-notification":"\uDB85\uDF3B", "error":"\uDB82\uDE04", "error-notification":"\uDB82\uDE04", "network-notification":"\uDB83\uDC8A", "battery-notification":"\uDB84\uDCCD", "update-notification":"\uDB81\uDEB0", "music-notification":"\uEC1B", "volume-notification":"\uDB81\uDFC5", "dnd":"\uDB84\uDD6D", "none":"\uDB80\uDF65" })
    css: "notification"
    tooltip: ""
    // dunst signals every counter it exposes and rewrites the archive on each
    // notification, so one subscriber replaces the poll. interval is now only
    // how fast a dead helper gets respawned
    readonly property string script: shell.home + "/.local/lib/hypr/notify/notifications.py"
    command: [root.script, "--watch"]
    polling: false; streaming: true; interval: 5000
    property bool popupEnabled: true
    property bool activeOnly: false
    // what the bell says about notifications archived since the panel was last
    // opened: "dot", "count", "highlight" (recolour the bell itself), or "none"
    property string badge: "dot"
    // nudge the badge off the glyph's top-right corner; positive pushes it right
    // and down. a 2-element array would read as TRBL next to margin/padding
    readonly property real badgeOffsetX: box.badgeOffsetX || 0
    readonly property real badgeOffsetY: box.badgeOffsetY || 0
    // the dot's diameter, or the em the count glyph draws at. Only one badge is
    // ever shown, so one key sizes it, and each mode defaults to its own size
    readonly property real badgeSize: box.badgeSize || (badge === "count" ? 13 : 6)
    readonly property bool paused: output.paused === true
    readonly property int unread: output.unread || 0
    readonly property bool marked: unread > 0 && badge !== "none"
    // md-numeric_<n>_circle draws the digit knocked out of the disc, so the face
    // centres it. The ten of them alternate with their _outline twins from
    // md-numeric_0_circle; past nine there is only md-numeric_9_plus_circle
    readonly property string countGlyph: unread > 9
        ? "\u{f0cb2}" : String.fromCodePoint(0xf0c9e + unread * 2)
    active: paused
    visible: activeOnly ? paused : text !== ""
    textColor: marked && badge === "highlight"
        ? shell.role("accent", shell.foreground)
        : box.content !== undefined ? styleColor("content")
        : active ? shell.role("act_fg", shell.foreground) : shell.foreground
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

    // a derived type's children stack above the base's, so these sit over the bell
    Rectangle {
        visible: root.marked && root.badge === "dot"
        x: root.paintedLabelBounds.x + root.paintedLabelBounds.width - width + root.badgeOffsetX
        y: root.paintedLabelBounds.y + root.badgeOffsetY
        width: Style.px(root.badgeSize); height: width
        radius: width / 2
        color: root.shell.role("accent", root.shell.foreground)
    }
    Text {
        visible: root.marked && root.badge === "count"
        x: root.paintedLabelBounds.x + root.paintedLabelBounds.width - paintedWidth + root.badgeOffsetX
        y: root.paintedLabelBounds.y + root.badgeOffsetY
        text: root.countGlyph
        color: root.shell.role("accent", root.shell.foreground)
        font.family: root.shell.iconGlyphFont
        font.pixelSize: Style.px(root.badgeSize)
    }

    NotificationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

PopupCard {
    id: root
    popupName: "powermenu"
    contentWidth: Style.px(330)
    contentHeight: menu.implicitHeight + padding * 2
    borderColor: shell.role("act_br", shell.accent)
    borderOpacity: .9

    property var pendingAction: null
    property var status: ({ suspend: true, hibernate: false, uptime: 0, user: Quickshell.env("USER"), host: "" })
    readonly property color dim: shell.alpha(shell.foreground, .55)
    readonly property color urgent: shell.role("error", shell.foreground)
    readonly property string helper: shell.home + "/.local/lib/hypr/session/power-menu.sh"
    readonly property var screenActions: [
        { id: "screen-off", icon: "󱍳", title: "Turn screens off", detail: "Wake them with the mouse or a key", command: [helper, "screen-off"] },
        { id: "lock", icon: "", title: "Lock", detail: "Password or fingerprint to return", command: ["hyprshell", "session/lock-screen.sh"] }
    ]
    readonly property var sessionActions: [
        status.suspend ? { id: "suspend", icon: "󰒲", title: "Suspend", detail: "Sleep to RAM", command: ["hyprshell", "session/suspend.sh"] } : null,
        status.hibernate ? { id: "hibernate", icon: "󰤁", title: "Hibernate", detail: "Sleep to disk, survives a flat battery", command: [helper, "hibernate"] } : null,
        { id: "shutdown", icon: "󰐥", title: "Shutdown", detail: "Power the machine off", destructive: true, command: ["hyprshell", "system/powerctl.sh", "shutdown"] },
        { id: "reboot", icon: "󰜉", title: "Reboot", detail: "Restart the machine", destructive: true, command: ["hyprshell", "system/powerctl.sh", "reboot"] },
        { id: "logout", icon: "󰍃", title: "Logout", detail: "End the Hyprland session", destructive: true, command: ["hyprshell", "logout"] }
    ].filter(Boolean)
    readonly property var actions: screenActions.concat(sessionActions)
    readonly property string sessionText: [status.user && status.host ? status.user + "@" + status.host : status.user, uptime(status.uptime)].filter(Boolean).join(" · ")

    function uptime(seconds) {
        const total = Math.max(0, Math.floor(Number(seconds) || 0)), days = Math.floor(total / 86400)
        const hours = Math.floor(total % 86400 / 3600), minutes = Math.floor(total % 3600 / 60)
        return days ? "up " + days + "d " + hours + "h" : hours ? "up " + hours + "h " + minutes + "m" : minutes ? "up " + minutes + "m" : ""
    }
    function loadStatus(raw) { try { status = JSON.parse(raw) } catch (error) {} }
    function run(action) { shell.closePopup(); shell.run(action.command) }
    function activate(action) {
        if (action.destructive) { pendingAction = action; confirm.selectedIndex = 1 }
        else run(action)
    }
    function handleKey(event) {
        if (confirm.opened) return confirm.handleKey(event)
        const key = String(event.text || "").toLowerCase(), number = parseInt(key)
        if (key === "j" || key === "k") { moveCursor(key === "j" ? 1 : -1); return true }
        if (number > 0 && number <= actions.length) { activate(actions[number - 1]); return true }
        if (event.key === Qt.Key_Space) { activateCursor(); return true }
        return defaultKey(event)
    }
    onOpenChanged: if (open && !statusProc.running) statusProc.running = true
    Component.onCompleted: statusProc.running = true

    component ActionRow: PopupRow {
        required property var action
        required property int number
        readonly property color actionColor: action.destructive && (hovered || cursored) ? root.urgent : root.shell.foreground
        width: menu.width; shell: root.shell; icon: action.icon; title: action.title; detail: action.detail; value: String(number)
        iconColor: actionColor; titleColor: actionColor; valueColor: root.dim
        onClicked: root.activate(action)
    }

    Column {
        id: menu
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.md

        Row {
            width: parent.width; spacing: Style.xxl
            Text { width: Style.px(30); anchors.verticalCenter: parent.verticalCenter; text: "󰐥"; color: root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.px(27); horizontalAlignment: Text.AlignHCenter }
            PopupHero { width: parent.width - Style.px(30) - parent.spacing; shell: root.shell; title: "Power"; status: root.sessionText }
        }
        PopupSection { shell: root.shell; text: "SCREEN" }
        Repeater {
            model: root.screenActions
            ActionRow { required property var modelData; required property int index; action: modelData; number: index + 1 }
        }
        PopupSection { shell: root.shell; text: "SESSION"; topPadding: Style.lg }
        Repeater {
            model: root.sessionActions
            ActionRow { required property var modelData; required property int index; action: modelData; number: root.screenActions.length + index + 1 }
        }
        PopupSeparator { shell: root.shell }
        Text {
            width: parent.width; text: "↑↓/jk move · 1–" + root.actions.length + " jump · enter select · esc close"
            horizontalAlignment: Text.AlignHCenter; color: root.dim
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    Process {
        id: statusProc
        command: [root.helper, "status"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadStatus(text) }
    }
    ConfirmDialog {
        id: confirm
        z: 2; anchors.fill: parent; opened: root.pendingAction !== null
        message: root.pendingAction ? (root.pendingAction.id === "logout" ? "Log out of this session?" : root.pendingAction.title + " now?") : ""
        confirmText: root.pendingAction ? root.pendingAction.title : "Confirm"
        background: root.background; foreground: root.shell.foreground; selectedText: root.urgent; fontFamily: root.shell.fontFamily; cornerRadius: root.shell.rounding
        onCanceled: root.pendingAction = null
        onConfirmed: { const action = root.pendingAction; root.pendingAction = null; root.run(action) }
    }
}

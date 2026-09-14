pragma ComponentBehavior: Bound
import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupEnabled: true
    css: "github.notifications"
    textColor: root.shell.role(output.class === "error" ? "error" : ["degraded", "security", "inbox-security"].includes(output.class) ? "warning" : "success", root.shell.foreground)
    command: ["hyprshell", "github-notifications"]
    interval: 3600000
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["xdg-open", "https://github.com/notifications"])
        : root.shell.togglePopup("github")
    GithubPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

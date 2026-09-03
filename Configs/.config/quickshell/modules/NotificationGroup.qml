pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showGithub: true
    shell: root.shell; css: "notification"; radius: root.shell.moduleRadius
    secondaryAvailable: root.showGithub
    holdOpen: ["notifications", "github"].includes(root.shell.popupName)
    primary: Component { NotificationButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
    secondary: Component { ScriptButton {
        id: githubModule
        shell: root.shell; css: "github.notifications"
        textColor: root.shell.role(output.class === "degraded" ? "warning" : output.class === "error" ? "error" : "success", root.shell.foreground)
        command: ["hyprshell", "github-notifications"]; interval: 3600000
        onClicked: button => button === Qt.RightButton
            ? root.shell.run(["xdg-open", "https://github.com/notifications"])
            : root.shell.togglePopup("github")
        GithubPopup { anchorItem: githubModule; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
}

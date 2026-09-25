pragma ComponentBehavior: Bound
import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupEnabled: true
    css: "github"
    command: ["hyprshell", "github-notifications"]
    interval: 3600000
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["xdg-open", "https://github.com/notifications"])
        : root.shell.togglePopup("github")
    GithubPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; onModuleRefreshRequested: root.refresh() }
}

pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showGithub: true
    property string badge: "dot"
    shell: root.shell; css: "notification-group"; radius: root.shell.moduleRadius
    secondaryAvailable: root.showGithub
    holdOpen: ["notifications", "github"].includes(root.shell.popupName)
    primary: Component { NotificationButton { shell: root.shell; popupEnabled: root.popupsAllowed; badge: root.badge } }
    secondary: Component { GithubButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
}

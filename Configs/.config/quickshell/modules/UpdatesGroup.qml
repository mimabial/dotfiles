pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    // updates take the head; agentsFirst pins agents there instead
    property bool agentsFirst: false
    css: "updates-agents"; reverse: true
    holdOpen: ["updates", "agents"].includes(root.shell.popupName)
    slots: root.agentsFirst ? [agentsView, updateView] : [updateView, agentsView]
    Component { id: updateView; UpdatesButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
    Component { id: agentsView; AgentsButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
}

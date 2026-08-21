import QtQuick
import QtQuick.Layouts
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool hasUpdates: false
    css: "updates-agents"; reverse: true
    holdOpen: ["updates", "agents"].includes(root.shell.popupName)
    primary: root.hasUpdates ? updateView : agentsView
    secondary: root.hasUpdates ? agentsView : updateView
    Component { id: updateView; UpdatesButton {
        shell: root.shell; popupEnabled: root.popupsAllowed
        onPendingChanged: root.hasUpdates = pending > 0
    } }
    Component { id: agentsView; AgentsButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
}

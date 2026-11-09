pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    property bool loaded: false
    opensPopup: true
    readonly property int dueCount: root.shell.dueTasks?.count ?? 0
    property bool showBadge: true

    css: "tasks"
    text: ""
    tooltip: ""
    active: root.shell.popupName === "tasks"
    badgeText: showBadge && dueCount > 0 ? root.countText(dueCount) : ""
    onClicked: { root.loaded = true; root.shell.togglePopup("tasks") }

    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.popupEnabled && root.shell.popupName === "tasks") root.loaded = true
        }
    }
    Loader {
        active: root.loaded; visible: false
        sourceComponent: Component {
            TasksPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs as Bar

Bar.BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var service: shell.altscape
    css: "altscape"
    opensPopup: true
    text: "󰕰"
    tooltip: service.displayName
    active: shell.popupName === "altscape"
    onClicked: service.togglePanel()
    Bar.AltscapePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

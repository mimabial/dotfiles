import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property bool shown: Mirroring.active
    css: "mirroring"; text: "󰍺"; symbol: "video-joined-displays"; symbolContext: "devices"
    onClicked: shell.togglePopup("mirroring-menu")
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "mirroring-menu"; settings: "Display"; settingsPopup: root.shell.liveModules.includes("display-menu") ? "display-menu-settings" : "monitor"
        PopupToggleRow { width: parent.width; shell: root.shell; title: "Screen Mirroring"; checked: Mirroring.active; onToggled: Mirroring.toggle() }
    }
}

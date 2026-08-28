import QtQuick

BarButton {
    id: root
    property bool popupEnabled: true
    css: "powermenu"
    text: "󰨚"
    active: shell.popupName === "powermenu"
    onClicked: shell.togglePopup("powermenu")

    PowerMenuPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

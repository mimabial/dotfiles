import QtQuick

BarButton {
    id: root
    property bool popupEnabled: true
    css: "hyprmenu"; text: ""
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "menutree"])
        : button === Qt.MiddleButton ? shell.run(["kitty"]) : shell.togglePopup("start")
    StartPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

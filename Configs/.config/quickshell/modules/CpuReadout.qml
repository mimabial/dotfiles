import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "cpu"
    tooltip: ""
    command: ["hyprshell", "cpu"]; interval: 5000
    textColor: root.box.content !== undefined ? root.styleColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("cpu")
    SysinfoPopup { popupName: "cpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "cpu"] }
}

import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "cpuinfo"
    command: ["hyprshell", "cpuinfo"]; interval: 5000
    textColor: root.box.content !== undefined ? root.boxColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("cpu")
    SysinfoPopup { popupName: "cpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "cpuinfo"] }
}

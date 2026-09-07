import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "disk"
    command: ["hyprshell", "sysinfo/diskinfo"]; interval: 600000
    textColor: root.box.content !== undefined ? root.boxColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("disk")
    SysinfoPopup { popupName: "disk"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "sysinfo/diskinfo"]; pollInterval: 30000 }
}

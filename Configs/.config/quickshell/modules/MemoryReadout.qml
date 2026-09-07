import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "memory"
    tooltip: ""
    command: ["hyprshell", "sysinfo/meminfo"]; interval: 30000
    textColor: root.box.content !== undefined ? root.boxColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("memory")
    SysinfoPopup { popupName: "memory"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "sysinfo/meminfo"] }
}

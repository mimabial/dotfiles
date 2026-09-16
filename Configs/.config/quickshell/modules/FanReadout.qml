import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "fanspeedinfo"
    command: ["hyprshell", "sysinfo/fanspeedinfo"]; interval: 10000
    useAlt: !root.vertical
    tooltip: root.vertical ? root.output.tooltip || "" : ""
    textColor: root.box.content !== undefined ? root.styleColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("fan")
        root.shell.run(["hyprshell", "sysinfo/fanspeedinfo", "--toggle"], root.refresh)
    }
    SysinfoPopup {
        popupName: "fan"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed
        command: ["hyprshell", "sysinfo/fanspeedinfo"]
        switchCommand: ["hyprshell", "sysinfo/fanspeedinfo", "--use"]
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    gap: 0
    iconLine: 17
    iconPadRight: 4
    css: "custom-fanspeedinfo"; fontWeight: Font.Bold
    command: ["hyprshell", "sysinfo/fanspeedinfo"]; interval: 10000
    textColor: root.shell.role("c7", root.shell.foreground)
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("fan")
        root.shell.run(["hyprshell", "sysinfo/fanspeedinfo", "--toggle"])
        root.refresh(300)
    }
    SysinfoPopup {
        popupName: "fan"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed
        command: ["hyprshell", "sysinfo/fanspeedinfo"]
        switchCommand: ["hyprshell", "sysinfo/fanspeedinfo", "--use"]
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    gap: 5
    iconLine: 20
    iconPadRight: 3
    css: "memory"; fontWeight: Font.Bold
    command: ["hyprshell", "sysinfo/meminfo"]; interval: 30000
    textColor: root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("memory")
    SysinfoPopup { popupName: "memory"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "sysinfo/meminfo"] }
}

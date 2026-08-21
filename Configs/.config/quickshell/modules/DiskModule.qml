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
    gap: 0
    css: "disk"; fontWeight: Font.Bold
    command: ["hyprshell", "sysinfo/diskinfo"]; interval: 600000
    textColor: root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("disk")
    SysinfoPopup { popupName: "disk"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "sysinfo/diskinfo"]; pollInterval: 30000 }
}

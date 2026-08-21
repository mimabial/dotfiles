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
    gap: 6
    iconLine: 21
    iconPadRight: 1
    css: "custom-cpuinfo"; fontWeight: Font.Bold
    command: ["hyprshell", "cpuinfo"]; interval: 5000
    textColor: root.shell.role("c7", root.shell.foreground)
    onClicked: root.shell.togglePopup("cpu")
    SysinfoPopup { popupName: "cpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "cpuinfo"] }
}

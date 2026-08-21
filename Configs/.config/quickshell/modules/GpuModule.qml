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
    iconPadRight: 3
    css: "custom-gpuinfo"; fontWeight: Font.Bold
    command: ["hyprshell", "gpuinfo"]; interval: 60000
    textColor: root.shell.role("c7", root.shell.foreground)
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("gpu")
        root.shell.run(["hyprshell", "gpuinfo", "--toggle"])
        root.refresh(300)
    }
    SysinfoPopup { popupName: "gpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "gpuinfo"]; switchCommand: ["hyprshell", "gpuinfo", "--use"] }
}

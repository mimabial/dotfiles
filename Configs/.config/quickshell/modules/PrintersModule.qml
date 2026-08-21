import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-printers"
    command: ["hyprshell", "system/printers", "--waybar"]; interval: 10000
    onClicked: root.shell.togglePopup("printers")
    PrintersPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

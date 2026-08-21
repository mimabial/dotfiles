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
    css: "custom-weather.minmax"
    command: ["hyprshell", "weather", "-m"]; interval: 3600000
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "network.speed"
    command: ["hyprshell", "sysinfo/network-speed"]; interval: 3000
}

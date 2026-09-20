import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    property bool vertical: true
    css: "network.speed"; tooltip: ""
    command: root.vertical
        ? ["hyprshell", "sysinfo/network-speed"]
        : ["hyprshell", "sysinfo/network-speed", "--alt"]
    interval: 3000
    textColor: root.box.content !== undefined ? root.styleColor("content")
        : root.shell.role("c7", root.shell.foreground)
}

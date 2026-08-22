import QtQuick

BarButton {
    css: "powermenu"
    text: "󰨚"
    tooltip: "Session"
    onClicked: shell.run(["hyprshell", "logout-launch.sh", "1"])
}

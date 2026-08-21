import QtQuick

BarButton {
    css: "custom-powermenu"
    text: "󰨚"
    tooltip: "Session"
    onClicked: shell.run(["hyprshell", "logout-launch.sh", "1"])
}

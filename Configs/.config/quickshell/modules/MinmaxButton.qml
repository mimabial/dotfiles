import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "weather.minmax"
    command: ["hyprshell", "weather", "-m"]; interval: 3600000
}

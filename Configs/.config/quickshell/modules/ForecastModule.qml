import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showMinMax: false
    shell: root.shell; css: "forecast"; Layout.fillWidth: true
    primary: Component { ScriptButton {
        id: weatherButton
        shell: root.shell; css: "custom-weather"; command: ["hyprshell", "weather"]; interval: 600000; textColor: root.shell.role("c2", root.shell.foreground)
        onClicked: root.shell.togglePopup("weather")
        WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondaryAvailable: root.showMinMax
    secondary: Component { ScriptButton {
        shell: root.shell; css: "custom-weather.minmax"
        command: ["hyprshell", "weather", "-m"]; interval: 3600000
    } }
}

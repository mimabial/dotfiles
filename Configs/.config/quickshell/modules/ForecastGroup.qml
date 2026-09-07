pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showMinMax: false
    property bool showSunrise: false
    property bool showSunset: false
    property bool showUnit: true
    shell: root.shell; css: "forecast"; Layout.fillWidth: true
    secondaryAvailable: root.showMinMax || root.showSunrise || root.showSunset
    slots: [weatherSlot].concat(root.showMinMax ? [minmaxSlot] : [])
        .concat(root.showSunrise ? [sunriseSlot] : [])
        .concat(root.showSunset ? [sunsetSlot] : [])

    Component { id: weatherSlot; StackedReadout {
        id: weatherButton
        shell: root.shell; css: "weather"; tooltip: ""; interval: 600000
        command: root.showUnit ? ["hyprshell", "weather"] : ["hyprshell", "weather", "--no-unit"]
        // c2 unless a style file names a colour; setting it on "weather" itself
        // would also repaint minmax/sunrise/sunset, which inherit that key
        textColor: weatherButton.box.content !== undefined ? weatherButton.boxColor("content")
            : root.shell.role("c2", root.shell.foreground)
        onClicked: root.shell.togglePopup("weather")
        WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: minmaxSlot; ScriptButton {
        shell: root.shell; css: "weather.minmax"
        command: ["hyprshell", "weather", "-m"]; interval: 3600000
    } }
    // the vertical bars take the stacked form; --alt is the one-line spelling
    Component { id: sunriseSlot; StackedReadout {
        shell: root.shell; css: "weather.sunrise"
        command: ["hyprshell", "weather", "-s"]; interval: 3600000
    } }
    Component { id: sunsetSlot; StackedReadout {
        shell: root.shell; css: "weather.sunset"
        command: ["hyprshell", "weather", "-S"]; interval: 3600000
    } }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

GridLayout {
    id: root
    required property var shell
    property bool popupsAllowed: true
    readonly property var readouts: Weather.readouts()
    flow: GridLayout.LeftToRight
    rowSpacing: 0; columnSpacing: 0

    Repeater {
        model: root.readouts
        BarButton {
            required property string modelData
            readonly property var reading: (Weather.output.readouts || {})[modelData]
            shell: root.shell
            css: modelData === "temp" ? "weather" : "weather." + modelData
            leadingIcon: reading && reading.icon ? reading.icon : ""
            text: reading ? (reading.value || reading.text) : ""
            visible: text !== ""
            Layout.fillHeight: true
            onClicked: root.shell.togglePopup("weather")
        }
    }
    WeatherPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

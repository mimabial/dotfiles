import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool activeOnly: false
    readonly property bool sunsetActive: shell.sunsetEnabled === "1"
    css: "hyprsunset"
    active: sunsetActive
    visible: !activeOnly || sunsetActive
    text: sunsetActive ? "󱩌" : "󱩍"
    tooltip: "<b>Night light</b>\n" + (sunsetActive ? "Active" : "Inactive")
        + "\nLeft: Settings\nRight: Toggle"
    onClicked: button => button === Qt.RightButton
        ? shell.run(["hyprshell", "hyprsunset", "-t", "-q"])
        : shell.togglePopup("hyprsunset")

    HyprsunsetPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

import QtQuick
import Quickshell.Services.UPower

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property bool performance: PowerProfiles.profile === PowerProfile.Performance
    readonly property bool saver: PowerProfiles.profile === PowerProfile.PowerSaver
    css: performance ? "powerprofile.performance" : saver ? "powerprofile.power-saver" : "powerprofile"
    text: PowerProfiles.profile === PowerProfile.Performance ? "󱐌" : PowerProfiles.profile === PowerProfile.PowerSaver ? "󰌪" : "󰗑"
    // power-profiles owns the GameMode lock and the list of profiles that exist
    onClicked: button => button === Qt.RightButton
        ? shell.run(["hyprshell", "system/power-profiles", "--cycle"])
        : shell.togglePopup("power")

    PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

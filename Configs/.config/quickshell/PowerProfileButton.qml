import QtQuick
import Quickshell.Services.UPower

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property bool performance: PowerProfiles.profile === PowerProfile.Performance
    readonly property bool saver: PowerProfiles.profile === PowerProfile.PowerSaver
    css: performance ? "power-profiles-daemon.performance" : saver ? "power-profiles-daemon.power-saver" : "power-profiles-daemon"
    radius: shell.moduleRadius
    text: PowerProfiles.profile === PowerProfile.Performance ? "" : PowerProfiles.profile === PowerProfile.PowerSaver ? "" : ""
    textColor: shell.role(performance ? "c3" : saver ? "c6" : "fg", shell.foreground)
    onClicked: button => button === Qt.RightButton
        ? PowerProfiles.profile = performance ? PowerProfile.PowerSaver : PowerProfiles.profile + 1
        : shell.togglePopup("power")

    PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

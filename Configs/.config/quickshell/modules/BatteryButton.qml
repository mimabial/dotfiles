import QtQuick
import Quickshell.Services.UPower
import ".."
import "StatusSymbols.js" as StatusSymbols

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property string popupName: "battery"
    readonly property string settingsPopupName: popupName + "-settings"
    readonly property var battery: UPower.displayDevice
    symbol: StatusSymbols.battery(battery, UPower.onBattery)
    readonly property bool shown: battery.isPresent
    css: "battery"
    onClicked: shell.togglePopup(root.popupName)
    PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: root.settingsPopupName }
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: root.popupName; settings: "Battery"; settingsPopup: root.settingsPopupName
        PopupRow {
            width: parent.width; shell: root.shell; interactive: false; title: "Battery"; value: Math.round(root.battery.percentage * 100) + "%"
            detail: !UPower.onBattery ? "Power Source: Power Adapter"
                : "Power Source: Battery" + (root.battery.timeToEmpty > 0 ? " · " + root.shell.duration(root.battery.timeToEmpty) + " left" : "")
        }
        PopupToggleRow {
            width: parent.width; shell: root.shell; title: "Low Power Mode"; checked: PowerProfiles.profile === PowerProfile.PowerSaver
            onToggled: root.shell.run(["hyprshell", "system/powerprofiles", "--set", checked ? "balanced" : "power-saver"])
        }
    }
}

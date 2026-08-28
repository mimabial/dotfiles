import QtQuick
import Quickshell.Services.UPower
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showLogout: true
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: root.battery && root.battery.isPresent && root.battery.energyCapacity > 0
    css: "power"
    reverse: true
    fill: boxColor("fill")
    alwaysOpen: true
    slots: [powerSlot]

    Component { id: powerSlot; BarGroup {
        css: "powerconsumption"; vertical: root.vertical; reverse: root.reverse
        shell: root.shell
        holdOpen: root.shell.popupName === "power" || root.shell.popupName === "powermenu"
        // a machine with no battery still needs the drawer: logout lives in it
        slots: [profileSlot].concat(root.hasBattery ? [batterySlot] : []).concat(root.showLogout ? [logoutSlot] : [])
        Component { id: profileSlot; PowerProfileButton {
            shell: root.shell; popupEnabled: root.popupsAllowed
        } }
        Component { id: batterySlot; BatteryButton { shell: root.shell } }
        Component { id: logoutSlot; LogoutButton { shell: root.shell; popupEnabled: root.popupsAllowed } }
    } }
}

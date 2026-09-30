pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import ".."

BluetoothButton {
    id: root
    readonly property var paired: Bluetooth.devices.values.filter(device => device.paired || device.bonded || device.trusted)
    popupName: "bluetooth-menu"
    symbol: power === "off" ? "bluetooth-disabled" : "bluetooth-active"
    function deviceIcon(device) {
        const kind = String(device.icon)
        return kind.includes("audio") ? "󰋋" : kind.includes("mouse") ? "󰍽" : kind.includes("keyboard") ? "󰌌" : kind.includes("phone") ? "󰏲" : "󰂯"
    }
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "bluetooth-menu"; settings: "Bluetooth"; settingsPopup: "bluetooth"
        PopupToggleRow { width: parent.width; shell: root.shell; title: "Bluetooth"; checked: root.power !== "off"; onToggled: root.shell.run(["hyprshell", "bluetooth/power", "toggle"]) }
        Repeater {
            model: root.power === "off" ? [] : root.paired
            PopupRow {
                required property var modelData
                width: parent.width; shell: root.shell; icon: root.deviceIcon(modelData); title: modelData.name
                detail: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                iconColor: modelData.connected ? root.shell.accent : root.shell.alpha(root.shell.foreground, .55)
                onClicked: root.shell.run(["hyprshell", "bluetooth/device-action", modelData.connected ? "disconnect" : "connect", String(modelData.address)])
            }
        }
    }
}

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
    property bool showReadout: false
    css: "bluetooth"; reverse: true
    secondaryAvailable: root.showReadout
    holdOpen: root.shell.popupName === "bluetooth"
    primary: Component { ScriptButton {
        id: bluetoothButton
        shell: root.shell; css: "custom-bluetooth"
        command: ["hyprshell", "waybar/bluetooth"]; interval: 5000
        // omarchy: left opens the panel, right toggles the radio
        onClicked: button => {
            if (button !== Qt.RightButton) return root.shell.togglePopup("bluetooth")
            const adapter = Bluetooth.defaultAdapter
            if (adapter) adapter.enabled = !adapter.enabled
        }
        BluetoothPopup { anchorItem: bluetoothButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { ScriptButton {
        shell: root.shell; css: "custom-bluetooth.status"
        command: ["hyprshell", "waybar/bluetooth", "--status"]; interval: 5000
    } }
}

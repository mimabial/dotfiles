import QtQuick
import QtQuick.Layouts
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showPrinters: false
    reverse: true; secondaryAvailable: root.showPrinters
    holdOpen: ["disks", "printers"].includes(root.shell.popupName)
    primary: Component { ScriptButton {
        id: disksButton
        shell: root.shell; css: "custom-removable"
        command: ["hyprshell", "system/removable", "--waybar"]; interval: 5000
        onClicked: root.shell.togglePopup("disks")
        DisksPopup { anchorItem: disksButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { PrintersModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}

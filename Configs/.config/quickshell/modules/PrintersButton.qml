import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "printers"
    command: ["hyprshell", "system/printers", "--bar"]; interval: 10000
    onClicked: root.shell.togglePopup("printers")
    PrintersPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

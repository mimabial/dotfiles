import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    shell: root.shell; css: "color"; Layout.fillWidth: true
    holdOpen: ["colormode", "colorpicker"].includes(root.shell.popupName)
    primary: Component { ScriptButton {
        id: colorButton; Layout.fillWidth: true; shell: root.shell; css: "colormode"; command: ["hyprshell", "waybar/waybar.colormode"]; interval: 86400000; refreshKey: root.shell.palette
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("colormode") : root.shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
        ColorModePopup { anchorItem: colorButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { ColorPickerButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}

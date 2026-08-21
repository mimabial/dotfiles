import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "colormode"; command: ["hyprshell", "waybar/waybar.colormode"]; interval: 86400000; refreshKey: shell.palette
    onClicked: button => button === Qt.LeftButton ? shell.togglePopup("colormode") : shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
    ColorModePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

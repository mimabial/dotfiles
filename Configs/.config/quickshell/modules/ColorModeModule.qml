import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property string lastColor: ""
    function loadColor(raw) { const color = String(raw).trim().split("\n")[0] || ""; lastColor = /^#[0-9a-fA-F]{6}$/.test(color) ? color : "" }
    property FileView colorFile: FileView { path: root.shell.home + "/.cache/colorpicker/colors"; watchChanges: true; printErrors: false; onLoaded: root.loadColor(text()); onFileChanged: reload() }
    shell: root.shell; css: "color"; Layout.fillWidth: true
    holdOpen: ["colormode", "colorpicker"].includes(root.shell.popupName)
    primary: Component { ScriptButton {
        id: colorButton; Layout.fillWidth: true; shell: root.shell; css: "colormode"; command: ["hyprshell", "waybar/waybar.colormode"]; interval: 86400000; refreshKey: root.shell.palette
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("colormode") : root.shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
        ColorModePopup { anchorItem: colorButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { BarButton {
        id: pickerButton; Layout.fillWidth: true; shell: root.shell; css: "colorpicker"; text: ""; textColor: root.lastColor || root.shell.foreground; tooltip: "Color picker"
        onClicked: root.shell.togglePopup("colorpicker"); onWheeled: delta => root.shell.run(["hyprshell", "rofi/color-picker", delta > 0 ? "-u" : "-d"])
        ColorPickerPopup { anchorItem: pickerButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
}

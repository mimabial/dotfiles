import QtQuick
import Quickshell.Io
import ".."

// the glyph carries the last picked colour, so the button owns that state
// rather than the group it happens to sit in
BarButton {
    id: root
    property bool popupsAllowed: true
    property string lastColor: ""
    function loadColor(raw) {
        const color = String(raw).trim().split("\n")[0] || ""
        lastColor = /^#[0-9a-fA-F]{6}$/.test(color) ? color : ""
    }
    property FileView colorFile: FileView {
        path: root.shell.home + "/.cache/colorpicker/colors"
        watchChanges: true; printErrors: false
        onLoaded: root.loadColor(text()); onFileChanged: reload()
    }
    css: "colorpicker"; text: ""
    textColor: root.lastColor || root.shell.foreground
    tooltip: "Color picker"
    onClicked: root.shell.togglePopup("colorpicker")
    onWheeled: delta => root.shell.run(["hyprshell", "rofi/color-picker", delta > 0 ? "-u" : "-d"])

    ColorPickerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

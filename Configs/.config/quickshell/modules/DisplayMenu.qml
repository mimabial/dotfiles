import QtQuick
import ".."

DisplayButton {
    id: root
    popupName: "display-menu"
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; popupName: "display-menu"; settings: "Display"; settingsPopup: "monitor"
        PopupSlider {
            width: parent.width; shell: root.shell; label: "Display"; visible: Backlight.device !== ""
            minimum: .05; value: Backlight.percent / 100
            onReleased: value => root.shell.run(["brightnessctl", "set", Math.round(value * 100) + "%"], Backlight.refresh)
        }
        PopupToggleRow {
            width: parent.width; shell: root.shell; title: "Dark Mode"; checked: root.shell.colorMode === "dark"
            onToggled: root.shell.run(["hyprshell", "rofi/menutree", "--action", checked ? "style_color_mode_light" : "style_color_mode_dark"])
        }
        PopupToggleRow {
            width: parent.width; shell: root.shell; title: "Night Shift"; checked: root.shell.sunsetEnabled === "1"
            onToggled: root.shell.run(["hyprshell", "hyprsunset", "-t", "-q"])
        }
    }
}

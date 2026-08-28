import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    css: "backlight"
    text: Backlight.icon
    radius: shell.moduleRadius
    onClicked: shell.togglePopup("monitor")
    onWheeled: delta => {
        shell.run(["hyprshell", "brightness-control.sh", delta > 0 ? "i" : "d"])
        Backlight.nudge()
    }

    MonitorPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

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
    property bool sliderFirst: false
    shell: root.shell; css: "eyecare"; Layout.fillWidth: true
    holdOpen: root.shell.popupName === "hyprsunset"
    primary: Component { BarButton {
        id: monitorButton; shell: root.shell; css: "backlight"; text: Backlight.icon
        onClicked: root.shell.togglePopup("monitor"); onWheeled: delta => { root.shell.run(["hyprshell", "brightness-control.sh", delta > 0 ? "i" : "d"]); Backlight.nudge() }
        MonitorPopup { anchorItem: monitorButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { GridLayout { columns: 1; rowSpacing: 0; columnSpacing: 0
        ScriptButton {
            id: sunsetModule
            Layout.fillWidth: true; shell: root.shell; css: "custom-hyprsunset"
            Layout.row: root.sliderFirst ? 1 : 0; Layout.column: 0
            command: ["hyprshell", "hyprsunset", "-rq"]; interval: 86400000
            onClicked: button => button === Qt.RightButton
                ? root.shell.run(["hyprshell", "hyprsunset", "-t", "-q", "-P", "waybar:19"])
                : root.shell.togglePopup("hyprsunset")
            HyprsunsetPopup { anchorItem: sunsetModule; shell: root.shell; popupEnabled: root.popupsAllowed }
        }
        BrightnessSlider {
            Layout.fillWidth: true; shell: root.shell
            Layout.row: root.sliderFirst ? 0 : 1; Layout.column: 0
        }
        ScriptButton { Layout.row: 2; Layout.column: 0; Layout.fillWidth: true; id: caffeineEyecare; shell: root.shell; css: "custom-caffeine"; command: ["hyprshell", "waybar/caffeine.sh"]; interval: 2000; onClicked: button => { root.shell.run(["hyprshell", button === Qt.RightButton ? "session/toggle-audio-keep-awake.sh" : "session/toggle-keep-awake.sh"]); caffeineEyecare.refresh(300) } }
    } }
}

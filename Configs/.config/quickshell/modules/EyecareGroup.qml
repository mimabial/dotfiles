import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool sliderFirst: false
    property bool showSlider: true
    shell: root.shell; css: "eyecare"; Layout.fillWidth: true
    holdOpen: ["hyprsunset", "caffeine"].includes(root.shell.popupName)
    slots: root.sliderFirst ? [monitorSlot].concat(root.showSlider ? [sliderSlot] : []).concat([sunsetSlot, caffeineSlot])
        : [monitorSlot, caffeineSlot, sunsetSlot].concat(root.showSlider ? [sliderSlot] : [])

    Component { id: monitorSlot; DisplayButton {
        shell: root.shell; popupEnabled: root.popupsAllowed
    } }
    Component { id: sunsetSlot; HyprsunsetButton {
        shell: root.shell; popupsAllowed: root.popupsAllowed
    } }
    Component { id: sliderSlot; BrightnessSlider { shell: root.shell } }
    Component { id: caffeineSlot; CaffeineButton {
        shell: root.shell; popupsAllowed: root.popupsAllowed
    } }
}

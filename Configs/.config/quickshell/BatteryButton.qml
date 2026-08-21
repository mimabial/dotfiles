import QtQuick
import Quickshell.Services.UPower

BarButton {
    id: root
    readonly property var battery: UPower.displayDevice
    readonly property bool available: battery && battery.isPresent && battery.energyCapacity > 0
    css: "battery"
    visible: available
    text: battery ? Math.round(battery.percentage * 100) + "%" : ""
    tooltip: "Battery " + text
}

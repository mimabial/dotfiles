import QtQuick
import Quickshell.Services.UPower

BarButton {
    id: root
    readonly property var battery: UPower.displayDevice
    readonly property bool available: battery && battery.isPresent && battery.energyCapacity > 0
    css: "battery"
    visible: available
    text: battery ? Math.round(battery.percentage * 100) + "%" : ""
    readonly property string remaining: !root.available ? ""
        : UPower.onBattery ? (root.battery.timeToEmpty > 0 ? shell.duration(root.battery.timeToEmpty) + " to empty" : "")
        : root.battery.timeToFull > 0 ? shell.duration(root.battery.timeToFull) + " to full" : "Charged"
    tooltip: !root.available ? ""
        : (root.remaining === "" ? "" : root.remaining + " ") + root.text
            + " | " + Math.abs(root.battery.changeRate).toFixed(1) + " W"
}

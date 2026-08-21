import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

PopupCard {
    id: root
    popupName: "power"
    contentWidth: 380
    contentHeight: powerColumn.implicitHeight + 32
    readonly property var battery: UPower.displayDevice
    readonly property string sysfs: battery && battery.nativePath ? "/sys/class/power_supply/" + battery.nativePath : ""
    property int cycles: -1
    property int sysfsEnd: -1
    property int upowerEnd: -1
    property int upowerStart: -1
    // UPower reports the firmware's active limit; sysfs can lag behind it,
    // so it only serves as the fallback (same precedence as omarchy).
    readonly property int thresholdEnd: upowerEnd > 0 ? upowerEnd : sysfsEnd
    readonly property string thresholdText: upowerStart > 0 && upowerStart !== thresholdEnd
        ? upowerStart + "-" + thresholdEnd + "%" : thresholdEnd + "%"
    readonly property bool discharging: UPower.onBattery
    // omarchy: a limit is "holding" only on AC, below 99%, once the charge has
    // actually stopped flowing — otherwise it's still charging toward the cap.
    readonly property bool thresholdActive: !discharging && thresholdEnd > 0 && thresholdEnd < 99
        && battery && Math.round(battery.percentage * 100) >= thresholdEnd && Math.abs(battery.changeRate) <= 0.2
    readonly property bool full: battery && battery.state === UPowerDeviceState.FullyCharged && !thresholdActive
    function size() { return battery && battery.energyCapacity > 0 ? battery.energyCapacity.toFixed(1) + "Wh" : "\u2014" }
    function rate() { return battery ? Math.abs(battery.changeRate).toFixed(1) + "W" : "\u2014" }

    function duration(seconds) { const minutes = Math.round(seconds / 60); return minutes > 59 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m" }
    function profileName(profile) { return PowerProfile.toString(profile).replace(/([a-z])([A-Z])/g, "$1 $2") }
    function profileIcon(profile) { return profile === PowerProfile.Performance ? "" : profile === PowerProfile.PowerSaver ? "" : "" }

    Column {
        id: powerColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: 14
        PopupSection { shell: root.shell; text: "POWER" }
        Text { width: parent.width; text: root.battery && root.battery.isPresent ? Math.round(root.battery.percentage * 100) + "%" : "AC POWER"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 38; font.bold: true; horizontalAlignment: Text.AlignHCenter }
        Text { width: parent.width; text: root.battery && root.battery.isPresent ? (UPower.onBattery ? root.duration(root.battery.timeToEmpty) + " remaining" : root.battery.timeToFull > 0 ? root.duration(root.battery.timeToFull) + " until full" : "Connected to power") : "No battery detected"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter }
        Rectangle { visible: root.battery && root.battery.isPresent; width: parent.width; height: 7; radius: 4; color: root.shell.alpha(root.shell.foreground, .12); Rectangle { width: parent.width * (root.battery ? root.battery.percentage : 0); height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) } }
        Row {
            visible: root.battery && root.battery.isPresent
            width: parent.width; spacing: Style.xl
            Column {
                width: (parent.width - parent.spacing) / 2; spacing: Style.sm
                InfoPair { label: "Battery size"; value: root.size() }
                InfoPair { label: "Charge cycles"; value: root.cycles > 0 ? String(root.cycles) : "\u2014" }
            }
            Column {
                width: (parent.width - parent.spacing) / 2; spacing: Style.sm
                InfoPair {
                    label: root.thresholdActive ? "Charge limit" : root.discharging ? "Time left" : "Time to full"
                    value: root.thresholdActive ? root.thresholdText
                        : root.full ? "-"
                        : root.duration(root.discharging ? root.battery.timeToEmpty : root.battery.timeToFull)
                }
                InfoPair {
                    label: root.thresholdActive ? "Battery state" : root.discharging ? "Discharging" : "Charging"
                    value: root.thresholdActive ? "Holding" : root.full ? "-" : root.rate()
                }
            }
        }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "POWER PROFILE" }
        Repeater {
            model: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            PopupRow {
                required property var modelData
                visible: modelData !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                width: parent.width; shell: root.shell; icon: root.profileIcon(modelData); title: root.profileName(modelData); detail: modelData === PowerProfiles.profile ? "Active" : ""; active: modelData === PowerProfiles.profile
                onClicked: PowerProfiles.profile = modelData
            }
        }
    }

    function readThresholds(raw) {
        const end = String(raw).match(/charge-end-threshold:\s*(\d+)/)
        const start = String(raw).match(/charge-start-threshold:\s*(\d+)/)
        upowerEnd = end ? parseInt(end[1]) : -1
        upowerStart = start ? parseInt(start[1]) : -1
    }
    onOpenChanged: if (open && battery && battery.nativePath && !upowerRead.running) upowerRead.running = true
    property Process upowerRead: Process {
        command: ["upower", "-i", "/org/freedesktop/UPower/devices/battery_" + (root.battery ? root.battery.nativePath : "")]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.readThresholds(text) }
    }

    component InfoPair: Row {
        property string label: ""
        property string value: ""
        width: parent.width; spacing: Style.lg
        Text { id: pairLabel; text: parent.label; color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
        Text { id: pairValue; text: parent.value; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }

    property FileView cyclesFile: FileView {
        path: root.sysfs ? root.sysfs + "/cycle_count" : ""
        watchChanges: root.sysfs !== ""; printErrors: false
        onFileChanged: reload()
        onLoaded: root.cycles = parseInt(text()) || 0
    }
    property FileView thresholdFile: FileView {
        path: root.sysfs ? root.sysfs + "/charge_control_end_threshold" : ""
        watchChanges: root.sysfs !== ""; printErrors: false
        onFileChanged: reload()
        onLoaded: root.sysfsEnd = parseInt(text()) || -1
    }
}

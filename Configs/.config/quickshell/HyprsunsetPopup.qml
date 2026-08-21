import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "hyprsunset"
    contentWidth: 320
    contentHeight: sunsetColumn.implicitHeight + padding * 2

    property var report: ({})
    readonly property bool active: report.active === true
    readonly property var limits: report.limits || ({})
    readonly property int temperature: report.temperature || 4500
    readonly property int gamma: report.gamma || 100

    // -q keeps the script from firing a notification for every slider step
    function apply(mode, value) {
        shell.run(["hyprshell", "hyprsunset", "--cm", mode, "-s", String(Math.round(value)), "-q"])
        settle.restart()
    }
    function refresh() { if (!readProc.running) readProc.running = true }
    function toggle() {
        shell.run(["hyprshell", "hyprsunset", "-t", "-q", "-P", "waybar:19"])
        settle.restart()
    }

    onOpenChanged: if (open) refresh()

    property Process readProc: Process {
        command: ["hyprshell", "hyprsunset", "-rq"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 400; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: sunsetColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "NIGHT LIGHT" }

        Text {
            width: parent.width
            text: root.active ? "Active" : "Inactive"
            color: root.active ? root.shell.role("warning", root.shell.foreground)
                : root.shell.alpha(root.shell.foreground, .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        PopupSlider {
            width: parent.width; shell: root.shell
            label: "Temperature"
            valueText: Math.round(root.temperature) + "K"
            // the slider works in 0..1; the script clamps to its own bounds anyway
            readonly property int low: root.limits.tempMin || 3000
            readonly property int high: root.limits.tempMax || 10000
            value: (root.temperature - low) / Math.max(1, high - low)
            onChanged: fraction => root.apply("temp", low + fraction * (high - low))
        }

        PopupSlider {
            width: parent.width; shell: root.shell
            label: "Gamma"
            valueText: Math.round(root.gamma) + "%"
            readonly property int low: root.limits.gammaMin || 20
            readonly property int high: root.limits.gammaMax || 100
            value: (root.gamma - low) / Math.max(1, high - low)
            onChanged: fraction => root.apply("gamma", low + fraction * (high - low))
        }

        PopupSeparator { shell: root.shell }

        PopupRow {
            width: parent.width; shell: root.shell
            icon: root.active ? "󱩌" : "󱩍"
            title: root.active ? "Turn off" : "Turn on"
            detail: root.active ? "Restore normal colours" : "Apply saved settings"
            active: root.active
            onClicked: root.toggle()
        }
    }
}

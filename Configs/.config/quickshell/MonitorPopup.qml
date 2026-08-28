import QtQuick
import Quickshell
import Quickshell.Io

PopupCard {
    id: root
    popupName: "monitor"
    contentWidth: Style.px(380)
    contentHeight: monitorColumn.implicitHeight + padding * 2
    property int brightness: 0
    property var monitors: []
    property string pendingDisplay: ""
    property bool pendingDisplayEnabled: false
    readonly property int enabledDisplayCount: monitors.filter(monitor => monitor.enabled).length
    readonly property var internalMonitor: monitors.find(monitor => /^(eDP|LVDS)/.test(monitor.name)) || null
    // which display the scale buttons act on; empty means the focused one
    property string target: ""
    readonly property var targetMonitor: {
        for (const monitor of monitors) if (monitor.name === target) return monitor
        for (const monitor of monitors) if (monitor.focused) return monitor
        for (const monitor of monitors) if (monitor.enabled) return monitor
        return monitors.length ? monitors[0] : null
    }
    readonly property string scale: targetMonitor ? String(targetMonitor.scale) : ""
    property bool internalOn: true
    property bool mirrorOn: false
    property bool hasBacklight: false
    property var scales: [1]
    property var textStops: [12]
    readonly property int brightnessStep: Math.max(1, Number(Quickshell.env("BRIGHTNESS_STEPS")) || 5)

    function refresh() { if (!brightnessRead.running) brightnessRead.running = true; if (!monitorRead.running) monitorRead.running = true }
    function setBrightness(value) { brightness = Math.round(value * 100); brightnessSet.restart() }
    function parseMonitors(text) {
        try {
            const values = JSON.parse(text).map(monitor => Object.assign({}, monitor, { enabled: monitor.disabled !== true }))
            monitors = values
            if (target === "" || !values.some(m => m.name === target))
                target = (values.find(m => m.focused) || values.find(m => m.enabled) || values[0] || {}).name || ""
            internalOn = values.some(m => /^(eDP|LVDS)/.test(m.name) && m.enabled)
            mirrorOn = values.some(m => m.enabled && m.mirrorOf && m.mirrorOf !== "none")
            const pending = values.find(m => m.name === pendingDisplay)
            if (pending && pending.enabled === pendingDisplayEnabled) pendingDisplay = ""
        } catch (error) { console.warn("monitors: " + error) }
    }
    function setScale(value) {
        if (target === "" || !targetMonitor || !targetMonitor.enabled) return
        root.shell.run(["hyprshell", "system/monitor-scale", "-m", target, String(value)])
        monitorSettle.restart()
    }
    function toggleDisplay(monitor) {
        if (!monitor || pendingDisplay !== "" || monitor.enabled && enabledDisplayCount <= 1) return
        pendingDisplay = monitor.name
        pendingDisplayEnabled = !monitor.enabled
        displayAction.command = ["hyprshell", "system/monitor-output", monitor.enabled ? "off" : "on", monitor.name, "--quiet"]
        displayAction.running = true
    }
    function loadSteps(raw, key) { const values = String(raw).trim().split(/\s+/).map(Number).filter(isFinite); if (values.length) root[key] = values }
    function brightnessName(percent) {
        const steps = [[95, "Sun blast"], [80, "Solar flare"], [65, "Golden hour"], [45, "Even day"], [30, "Soft glow"], [20, "Lamp light"], [10, "Candlelit"]]
        for (const [floor, name] of steps) if (percent >= floor) return name
        return "Night owl"
    }
    onOpenChanged: if (open) refresh()

    readonly property int textIndex: {
        let best = 0, closest = Infinity
        for (let i = 0; i < textStops.length; ++i) {
            const distance = Math.abs(textStops[i] - Style.textSize)
            if (distance < closest) { closest = distance; best = i }
        }
        return best
    }

    property Process brightnessRead: Process { command: ["brightnessctl", "-m"]; stdout: SplitParser { onRead: line => { root.brightness = Number(line.split(",")[3].replace("%", "")); root.hasBacklight = true } } }
    property Process monitorRead: Process { command: ["hyprctl", "monitors", "all", "-j"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseMonitors(text) } }
    property Process displayAction: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.pendingDisplay = ""
            root.monitorSettle.restart()
        }
    }
    property Process scaleRead: Process { running: true; command: ["hyprshell", "system/monitor-scale", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadSteps(text, "scales") } }
    property Process textStepsRead: Process { running: true; command: ["hyprshell", "system/text-size", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadSteps(text, "textStops") } }
    property Timer monitorSettle: Timer { interval: 700; onTriggered: if (!root.monitorRead.running) root.monitorRead.running = true }
    property Timer brightnessSet: Timer { interval: 50; onTriggered: root.shell.run(["brightnessctl", "set", root.brightness + "%"]) }

    Column {
        id: monitorColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        PopupHero {
            shell: root.shell; title: "Display"
            status: root.hasBacklight ? root.brightnessName(root.brightness) : "fixed brightness"
        }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "BRIGHTNESS"; value: root.brightness + "%" }
        PopupSlider { width: parent.width; shell: root.shell; valueText: ""; value: root.brightness / 100; step: root.brightnessStep / 100; onChanged: value => root.setBrightness(value) }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "TEXT SIZE"; value: root.textStops[root.textIndex] + "px" }
        PopupSlider {
            width: parent.width; shell: root.shell
            valueText: ""
            maximum: root.textStops.length - 1
            step: 1
            tickCount: root.textStops.length
            value: root.textIndex
            onReleased: value => root.shell.run(["hyprshell", "system/text-size", String(root.textStops[Math.round(value)])])
        }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "SCALE"; value: root.monitors.length > 1 ? root.target : "" }
        Row {
            id: scaleRow
            width: parent.width; spacing: Style.xs
            readonly property int columns: root.scales.length
            readonly property real cellWidth: columns > 0 ? (width - spacing * (columns - 1)) / columns : 0
            Repeater {
                model: root.scales
                BarButton {
                    required property var modelData
                    shell: root.shell; text: modelData + "\u00d7"
                    implicitWidth: scaleRow.cellWidth; height: Style.controlHeight; fontSize: Style.caption
                    outline: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
                    active: root.scale === String(modelData)
                    enabled: root.targetMonitor && root.targetMonitor.enabled
                    onClicked: root.setScale(modelData)
                }
            }
        }
        PopupSeparator { visible: root.monitors.length > 1; shell: root.shell }
        PopupSection { visible: root.monitors.length > 1; shell: root.shell; text: "DISPLAYS" }
        Repeater {
            model: root.monitors.length > 1 ? root.monitors : []
            PopupRow {
                required property var modelData
                width: monitorColumn.width; shell: root.shell
                rightInset: Style.px(46)
                icon: /^(eDP|LVDS)/.test(modelData.name) ? "󰍹" : "󰍺"
                title: modelData.name + (modelData.focused ? "  ·  focused" : "")
                detail: root.pendingDisplay === modelData.name ? (root.pendingDisplayEnabled ? "Enabling…" : "Disabling…")
                    : modelData.enabled ? modelData.width + "\u00d7" + modelData.height + " @ " + Math.round(modelData.refreshRate) + "Hz" : "Disabled"
                value: modelData.enabled ? modelData.scale + "\u00d7" : ""
                active: modelData.enabled
                selected: modelData.name === root.target
                onClicked: root.target = modelData.name
                ToggleSwitch {
                    anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                    shell: root.shell
                    checked: modelData.enabled
                    enabled: root.pendingDisplay === "" && (!modelData.enabled || root.enabledDisplayCount > 1)
                    onToggled: root.toggleDisplay(modelData)
                }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰍹"; title: "Laptop display"; detail: root.internalOn ? "Enabled" : "Disabled"; active: root.internalOn; interactive: root.internalMonitor !== null; onClicked: root.toggleDisplay(root.internalMonitor) }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰍺"; title: "Display mirroring"; detail: root.mirrorOn ? "Enabled" : "Disabled"; active: root.mirrorOn; onClicked: { root.mirrorOn = !root.mirrorOn; root.shell.run(["hyprshell", "system/monitor-mirror", "toggle"]) } }
    }
}

import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "hyprsunset"
    contentWidth: Style.px(320)
    contentHeight: sunsetColumn.implicitHeight + padding * 2

    property var report: ({})
    property string savedSettings: ""
    property bool refreshPending: false
    readonly property bool active: report.active === true
    readonly property var limits: report.limits || ({})
    readonly property int temperature: report.temperature || 4500
    readonly property int gamma: report.gamma || 100

    function apply(mode, value) {
        const set = Math.round(value)
        report = Object.assign({}, report, mode === "temp" ? { temperature: set } : { gamma: set })
        shell.run(["hyprshell", "hyprsunset", "--cm", mode, "-s", String(set), "-q"], root.refresh)
    }
    function refresh() {
        if (readProcess.running) refreshPending = true
        else readProcess.running = true
    }
    function toggle() { shell.run(["hyprshell", "hyprsunset", "-t", "-q"], root.refresh) }

    onOpenChanged: if (open) refresh()

    property Process readProcess: Process {
        command: ["bash", root.shell.home + "/.local/lib/hypr/system/hyprsunset.sh", "-rq"]
        onRunningChanged: if (!running && root.refreshPending) {
            root.refreshPending = false
            root.refresh()
        }
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    FileView {
        path: root.shell.home + "/.local/state/hypr/staterc"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const settings = text().split("\n").filter(line => /^HYPRSUNSET_(TEMP|GAMMA|ENABLED)=/.test(line)).join("\n")
            if (settings === root.savedSettings) return
            root.savedSettings = settings
            if (root.open) root.refresh()
        }
    }

    Column {
        id: sunsetColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell; title: "Night light"; status: root.active ? "active" : "inactive"
            statusColor: root.active ? root.shell.role("warning", root.shell.foreground) : root.shell.mutedText
        }

        PopupSlider {
            width: parent.width; shell: root.shell
            label: "Temperature"
            valueText: Math.round(root.temperature) + "K"
            readonly property int low: root.limits.tempMin || 3000
            readonly property int high: root.limits.tempMax || 10000
            value: (root.temperature - low) / Math.max(1, high - low)
            onReleased: fraction => root.apply("temp", low + fraction * (high - low))
        }

        PopupSlider {
            width: parent.width; shell: root.shell
            label: "Gamma"
            valueText: Math.round(root.gamma) + "%"
            readonly property int low: root.limits.gammaMin || 20
            readonly property int high: root.limits.gammaMax || 100
            value: (root.gamma - low) / Math.max(1, high - low)
            onReleased: fraction => root.apply("gamma", low + fraction * (high - low))
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

import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "printers"
    contentWidth: 360

    property var report: ({})
    readonly property var printers: report.printers || []
    readonly property var jobs: report.jobs || []

    function refresh() { if (!listProc.running) listProc.running = true }
    function act(args) {
        actProc.running = false
        actProc.command = ["hyprshell", "system/printers"].concat(args)
        actProc.running = true
    }
    function sizeLabel(bytes) {
        const kb = Number(bytes) / 1024
        return kb >= 1024 ? (kb / 1024).toFixed(1) + " MB" : Math.round(kb) + " KB"
    }

    onOpenChanged: if (open) refresh()

    property Process listProc: Process {
        command: ["hyprshell", "system/printers", "--report"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) } catch (error) { root.report = ({}) }
        } }
    }
    property Process actProc: Process { onExited: settle.restart() }
    property Timer settle: Timer { interval: 500; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: printersColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "PRINTERS" }

        Text {
            visible: root.printers.length === 0
            width: parent.width; text: "No printers configured"
            color: root.shell.alpha(root.shell.foreground, .5)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        Repeater {
            model: root.printers
            PopupRow {
                required property var modelData
                width: printersColumn.width; shell: root.shell
                icon: modelData.state === "stopped" ? "\u{f042c}"
                    : modelData.state === "printing" ? "\u{f1296}" : "\u{f042a}"
                title: modelData.name + (modelData.default ? "  •  default" : "")
                detail: modelData.state === "stopped" ? "Stopped — queued jobs are held" : modelData.state
                value: modelData.state === "stopped" ? "Resume" : "Pause"
                active: modelData.state === "stopped"
                // left toggles the queue, right makes it the default
                onClicked: button => button === Qt.RightButton
                    ? root.act(["--default", modelData.name])
                    : root.act([modelData.state === "stopped" ? "--enable" : "--disable", modelData.name])
            }
        }

        PopupSeparator { visible: root.jobs.length > 0; shell: root.shell }
        PopupSection {
            visible: root.jobs.length > 0
            shell: root.shell; text: "QUEUE · " + root.jobs.length
        }

        Repeater {
            model: root.jobs
            PopupRow {
                required property var modelData
                width: printersColumn.width; shell: root.shell
                icon: "\u{f015a}"
                title: modelData.id
                detail: modelData.user + " — " + root.sizeLabel(modelData.size)
                value: "Cancel"
                onClicked: root.act(["--cancel", modelData.id])
            }
        }

        PopupSeparator { shell: root.shell }
        Row {
            width: parent.width; spacing: Style.xs
            PopupRow {
                width: (parent.width - Style.xs) / 2; shell: root.shell
                icon: "\u{f0a79}"; title: "Cancel all"
                onClicked: root.act(["--cancel-all"])
            }
            PopupRow {
                width: (parent.width - Style.xs) / 2; shell: root.shell
                icon: "\u{f0707}"; title: "CUPS"
                onClicked: { root.act(["--web"]); root.shell.closePopup() }
            }
        }
    }
}

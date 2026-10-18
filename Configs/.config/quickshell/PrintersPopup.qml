pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "Units.js" as Units

PopupCard {
    id: root
    popupName: "printers"
    contentWidth: Style.px(360)

    readonly property string script: shell.home + "/.local/lib/hypr/system/printers.sh"
    property var report: ({})
    property string error: ""
    readonly property var printers: report.printers || []
    readonly property var jobs: report.jobs || []
    readonly property var defaultPrinter: printers.find(printer => printer.default) || ({})

    function refresh() { if (!listProcess.running) listProcess.running = true }
    function act(args) {
        error = ""
        actProcess.running = false
        actProcess.command = ["bash", script].concat(args)
        actProcess.running = true
    }

    onOpenChanged: if (open) { error = ""; refresh() }

    property Process listProcess: Process {
        command: ["bash", root.script, "--report"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) } catch (error) { root.report = ({}) }
        } }
    }
    property Process actProcess: Process {
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = String(text).trim() }
        onExited: root.refresh()
    }
    property Timer printerPollTimer: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: printersColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero { shell: root.shell; title: "Printers"; status: root.printers.length > 0 ? root.printers.length + " configured" : "none configured" }

        Text {
            visible: text !== ""
            width: parent.width; wrapMode: Text.Wrap
            text: root.error || (root.printers.length === 0 ? "No printers configured" : "")
            color: root.error ? root.shell.role("error", root.shell.foreground) : root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        Column {
            width: parent.width; spacing: Style.xxs
            Repeater {
                model: root.printers
                PopupRow {
                    required property var modelData
                    width: printersColumn.width; shell: root.shell
                    icon: modelData.state === "stopped" ? "\u{f042c}"
                        : modelData.state === "printing" ? "\u{f1296}" : "\u{f042a}"
                    title: modelData.name + (modelData.default ? "  •  default" : "")
                    detail: [modelData.state === "stopped" ? (modelData.reason || "Stopped") + " — jobs held" : modelData.state,
                        modelData.transport].filter(part => part).join("  •  ")
                    value: modelData.state === "stopped" ? "Resume" : "Pause"
                    active: modelData.state === "stopped"
                    onClicked: button => button === Qt.RightButton
                        ? root.act(["--default", modelData.name])
                        : root.act([modelData.state === "stopped" ? "--enable" : "--disable", modelData.name])
                }
            }
        }

        PopupSeparator { visible: root.jobs.length > 0; shell: root.shell }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection {
                visible: root.jobs.length > 0
                shell: root.shell; text: "QUEUE"; value: root.jobs.length
            }

            Repeater {
                model: root.jobs
                PopupRow {
                    required property var modelData
                    width: printersColumn.width; shell: root.shell
                    icon: "\u{f015a}"
                    title: modelData.id
                    detail: modelData.user + " — " + Units.bytesText(modelData.size)
                    value: "Cancel"
                    onClicked: root.act(["--cancel", modelData.id])
                }
            }
        }

        PopupSeparator { shell: root.shell }
        RowLayout {
            width: parent.width; spacing: Style.xs
            PopupRow {
                Layout.fillWidth: true; shell: root.shell
                icon: "\u{f0a79}"; title: "Cancel all"
                onClicked: root.act(["--cancel-all"])
            }
            PopupRow {
                readonly property bool onUsb: root.defaultPrinter.transport === "usb"
                visible: !!root.defaultPrinter.transport
                Layout.fillWidth: true; shell: root.shell
                icon: onUsb ? "\u{f0317}" : "\u{f0553}"; title: onUsb ? "Use network" : "Use USB"
                onClicked: root.act(["--switch", root.defaultPrinter.name])
            }
        }
    }
}

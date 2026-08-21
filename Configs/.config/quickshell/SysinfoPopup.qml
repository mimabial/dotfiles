import QtQuick
import Quickshell.Io

// Renders whatever `rows` the producing script reports, so adding a metric is
// a change to the script alone.
PopupCard {
    id: root
    contentWidth: 320
    contentHeight: sysinfoColumn.implicitHeight + padding * 2

    required property list<string> command
    property int pollInterval: 3000
    // rotates the producer's selection; the panel only offers it when the
    // script reports more than one choice
    property list<string> switchCommand: []
    property var report: ({})
    readonly property var rows: report.rows || []
    readonly property var choices: report.choices || []

    function refresh() { if (!statProc.running) statProc.running = true }
    function switchTo(id) {
        shell.run(root.switchCommand.concat([id]))
        settle.restart()
        // the bar module is on its own long poll; nudge it so the glyph does
        // not lag the panel by up to a minute
        if (anchorItem && anchorItem.refresh) anchorItem.refresh(1500)
    }

    onOpenChanged: if (open) refresh()

    property Process statProc: Process {
        command: root.command
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 1200; onTriggered: root.refresh() }
    property Timer poll: Timer {
        interval: root.pollInterval; running: root.open; repeat: true
        onTriggered: root.refresh()
    }

    Column {
        id: sysinfoColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: String(root.report.title || "").toUpperCase() }

        Text {
            visible: root.rows.length === 0
            width: parent.width; text: "No data"
            color: root.shell.alpha(root.shell.foreground, .55)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        Column {
            visible: root.choices.length > 1 && root.switchCommand.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            Repeater {
                model: root.choices
                PopupRow {
                    required property var modelData
                    width: sysinfoColumn.width; shell: root.shell
                    title: modelData.label
                    detail: modelData.active ? "Active" : "Switch to this"
                    active: modelData.active
                    onClicked: if (!modelData.active) root.switchTo(modelData.id)
                }
            }
        }

        Repeater {
            model: root.rows
            Row {
                required property var modelData
                width: sysinfoColumn.width; spacing: Style.lg
                Text {
                    id: rowLabel
                    text: modelData.label
                    color: root.shell.alpha(root.shell.foreground, .6)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Text {
                    width: Math.max(0, parent.width - rowLabel.implicitWidth - parent.spacing)
                    text: modelData.value
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                    color: root.shell.foreground
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
            }
        }
    }
}

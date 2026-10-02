pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "wifiqr"
    keyboardHint: "Esc close"
    contentWidth: Style.px(260)
    contentHeight: qrColumn.implicitHeight + padding * 2

    property var rows: []
    property string ssid: ""
    property string error: ""

    onOpenChanged: if (open && !qrProc.running) { error = ""; qrProc.running = true }

    function load(raw) {
        const lines = String(raw || "").trim().split(/\r?\n/).filter(line => line !== "")
        if (lines.length && lines[0].indexOf("meta\t") === 0) {
            const fields = lines.shift().split("\t")
            ssid = fields.slice(3).join("\t")
        }
        // A ragged matrix would render a code that cannot scan — drop it instead.
        const square = lines.length > 0 && lines.every(line => line.length === lines.length)
        rows = square ? lines : []
        if (!square) error = "Could not read the network credentials"
    }

    property Process qrProc: Process {
        command: ["hyprshell", "system/network-qr"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text) root.error = String(text).trim() }
    }

    Column {
        id: qrColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero { shell: root.shell; title: "Share network"; status: root.ssid }
        Rectangle {
            visible: root.rows.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.px(212); height: width; color: "#ffffff"; radius: Style.xxs
            Grid {
                id: qrGrid
                anchors.centerIn: parent
                readonly property int size: root.rows.length
                readonly property real module: parent.width / Math.max(1, size)
                columns: size
                Repeater {
                    model: qrGrid.size * qrGrid.size
                    Rectangle {
                        required property int index
                        width: qrGrid.module; height: qrGrid.module
                        color: root.rows[Math.floor(index / qrGrid.size)].charAt(index % qrGrid.size) === "1"
                            ? "#111111" : "transparent"
                    }
                }
            }
        }
        Text {
            visible: root.rows.length === 0
            width: parent.width; wrapMode: Text.Wrap
            text: root.error || "Reading network credentials…"
            color: root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
    }
}

import QtQuick
import Quickshell.Io

// Its own panel, the way omarchy separates wifiqr from the network panel.
PopupCard {
    id: root
    popupName: "wifiqr"
    contentWidth: 260
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
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.rowGap

        PopupSection { shell: root.shell; text: "SHARE NETWORK" }
        Text {
            visible: root.ssid !== ""
            width: parent.width; text: root.ssid; elide: Text.ElideRight
            color: root.shell.foreground; font.family: root.shell.fontFamily
            font.pixelSize: Style.subtitle; font.bold: true
        }
        Rectangle {
            visible: root.rows.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 212; height: 212; color: "#ffffff"; radius: 2
            Grid {
                anchors.centerIn: parent
                readonly property int size: root.rows.length
                readonly property real module: 212 / Math.max(1, size)
                columns: size
                Repeater {
                    model: parent.size * parent.size
                    Rectangle {
                        required property int index
                        width: parent.module; height: parent.module
                        color: root.rows[Math.floor(index / parent.size)].charAt(index % parent.size) === "1"
                            ? "#111111" : "transparent"
                    }
                }
            }
        }
        Text {
            visible: root.rows.length === 0
            width: parent.width; wrapMode: Text.Wrap
            text: root.error || "Reading network credentials…"
            color: root.shell.alpha(root.shell.foreground, .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
    }
}

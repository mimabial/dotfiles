pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "wifiqr"
    keyboardHint: "Tab move · Enter · Ctrl+Tab panel · Esc"
    contentWidth: Style.px(260)
    contentHeight: qrColumn.implicitHeight + padding * 2

    property var rows: []
    property string ssid: ""
    property string error: ""
    property string iface: ""
    property string security: ""
    property string password: ""
    property bool revealing: false
    property bool refreshPending: false
    property bool passwordPending: false
    property int passwordRevision: 0

    onOpenChanged: {
        password = ""; revealing = false; rows = []; ssid = ""; iface = ""; security = ""; error = ""
        passwordRevision++; passwordPending = false
        if (open) {
            if (qrProc.running) refreshPending = true
            else qrProc.running = true
        } else {
            refreshPending = false
            qrProc.running = false
            passwordProc.running = false
        }
    }
    function togglePassword() {
        revealing = !revealing
        passwordRevision++
        if (!revealing) { password = ""; passwordProc.running = false }
        else {
            error = ""
            readPassword()
        }
    }
    function readPassword() {
        if (!open || !revealing) return
        if (passwordProc.running) { passwordPending = true; passwordProc.running = false; return }
        passwordReader.revision = passwordRevision
        passwordProc.command = [shell.home + "/.local/lib/hypr/system/network-qr.sh", "--password", iface]
        passwordProc.running = true
    }

    function load(raw) {
        if (!open || refreshPending) return
        const lines = String(raw || "").trim().split(/\r?\n/).filter(line => line !== "")
        if (lines.length && lines[0].indexOf("meta\t") === 0) {
            const fields = lines.shift().split("\t")
            iface = fields[1]
            security = fields[2]
            ssid = fields.slice(3).join("\t")
        }
        // A ragged matrix would render a code that cannot scan — drop it instead.
        const square = lines.length > 0 && lines.every(line => line.length === lines.length)
        rows = square ? lines : []
        if (!square) error = "Could not read the network credentials"
    }

    property Process qrProc: Process {
        command: [root.shell.home + "/.local/lib/hypr/system/network-qr.sh"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text && root.open && !root.refreshPending) root.error = String(text).trim() }
        onExited: if (root.refreshPending) { root.refreshPending = false; if (root.open) Qt.callLater(() => root.qrProc.running = true) }
    }
    property Process passwordProc: Process {
        id: passwordReader
        property int revision: 0
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (root.open && root.revealing && root.passwordRevision === passwordReader.revision) root.password = String(text) }
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (text && root.open && root.revealing && root.passwordRevision === passwordReader.revision) root.error = String(text).trim() }
        onExited: if (root.passwordPending) { root.passwordPending = false; Qt.callLater(root.readPassword) }
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
        PopupRow { visible: root.rows.length > 0 && root.security === "WPA"; width: parent.width; shell: root.shell; title: root.revealing ? "Hide password" : "Reveal password"; onClicked: root.togglePassword() }
        Text { visible: root.revealing; width: parent.width; text: root.passwordProc.running ? "Reading password…" : root.password; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        Text { visible: root.rows.length > 0 && root.error !== ""; width: parent.width; text: root.error; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.shell.urgent; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }
}

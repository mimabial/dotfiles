import QtQuick
import Quickshell.Io

BarButton {
    id: root
    property var command: []
    property var processEnvironment: ({})
    property int interval: 60000
    property var icons: ({})
    property string fallback: ""
    property bool useAlt: false
    property var refreshKey
    property var output: ({ text: "", tooltip: "" })
    readonly property string raw: String((useAlt ? output.alt : output.text) || icons[output.alt] || fallback || "")
    // Only go through rich text when the payload actually carries pango markup.
    // HTML collapses leading whitespace, and these scripts use it for alignment —
    // mediaplayer pads with a space so "04" sits under ":04".
    readonly property bool markup: raw.indexOf("<") >= 0
    readonly property string rendered: markup ? raw.replace(/<span size='([^']+)' color='([^']+)'>/g, "<span style='font-size:$1;color:$2'>").replace(/<span (?:color|foreground)='([^']+)'>/g, "<span style='color:$1'>").replace(/<span size='([^']+)'>/g, "<span style='font-size:$1'>").replace(/\r\n?|\n/g, "<br>").replace(/(^|<br>) /g, "$1&nbsp;") : raw
    text: rendered
    textFormat: markup ? Text.RichText : Text.PlainText
    tooltip: output.tooltip || ""
    visible: text !== ""
    function refresh(delay) { refreshDelay.interval = delay || 0; refreshDelay.restart() }
    onRefreshKeyChanged: refresh()

    Process {
        id: process
        command: root.command
        environment: root.processEnvironment
        stdout: SplitParser { onRead: line => {
            // some modules (bluetooth --status) emit bare text, not json
            try { root.output = JSON.parse(line) }
            catch (error) { root.output = { text: String(line), tooltip: "" } }
        } }
    }
    Timer {
        interval: root.interval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!process.running) process.running = true
    }
    Timer { id: refreshDelay; onTriggered: if (!process.running) process.running = true }
}

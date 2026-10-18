import QtQuick
import Quickshell.Io

BarButton {
    id: root
    property var command: []
    property var processEnvironment: ({})
    property int interval: 60000
    property bool polling: true
    property bool streaming: false
    property var icons: ({})
    property string fallback: ""
    property bool useAlt: false
    property var refreshKey
    property bool refreshPending: false
    property var output: ({ text: "", tooltip: "" })
    readonly property string providerText: String((useAlt ? output.alt : output.text) || icons[output.alt] || fallback || "")
    readonly property bool hasPangoMarkup: providerText.indexOf("<") >= 0
    readonly property string renderedProviderText: {
        if (!hasPangoMarkup) return providerText
        const styledSpans = providerText
            .replace(/<span size='([^']+)' color='([^']+)'>/g, "<span style='font-size:$1;color:$2'>")
            .replace(/<span (?:color|foreground)='([^']+)'>/g, "<span style='color:$1'>")
            .replace(/<span size='([^']+)'>/g, "<span style='font-size:$1'>")
        const htmlLines = styledSpans.replace(/\r\n?|\n/g, "<br>")
        return htmlLines.replace(/(^|<br>) /g, "$1&nbsp;")
    }
    text: renderedProviderText
    textFormat: hasPangoMarkup ? Text.RichText : Text.PlainText
    tooltip: output.tooltip || ""
    readonly property bool hasContent: text !== ""
    visible: hasContent
    property string indicator: ""
    function refresh() {
        if (providerProcess.running) {
            refreshPending = true
            if (streaming) providerProcess.running = false
        }
        else Qt.callLater(root.startProvider)
    }
    function startProvider() { if (!providerProcess.running) providerProcess.running = true }
    onRefreshKeyChanged: refresh()

    Connections {
        target: root.indicator ? root.shell : null
        function onIndicatorRefreshSerialChanged() {
            if (["all", root.indicator].includes(root.shell.indicatorRefreshTarget)) root.refresh()
        }
    }

    Process {
        id: providerProcess
        command: root.command
        environment: root.processEnvironment
        onRunningChanged: if (!running && root.refreshPending) {
            root.refreshPending = false
            root.refresh()
        }
        onExited: exitCode => {
            if (root.streaming && exitCode === 0) root.refresh()
        }
        stdout: SplitParser { onRead: line => {
            try { root.output = JSON.parse(line) }
            catch (error) { root.output = { text: String(line), tooltip: "" } }
        } }
    }
    Timer {
        id: providerPollTimer
        interval: root.interval; running: root.polling && !root.streaming; repeat: true; triggeredOnStart: true
        onTriggered: root.startProvider()
    }
    Component.onCompleted: if (streaming) refresh()
}

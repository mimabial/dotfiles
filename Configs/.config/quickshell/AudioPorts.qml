pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root
    property var sinks: []
    property bool refreshPending: false
    property var processEnvironment: ({ LC_ALL: "C" })
    function port(name) { const sink = sinks.find(sink => sink.name === name); return sink ? String(sink.active_port || "") : "" }
    function refresh() {
        if (probe.running) refreshPending = true
        else { refreshPending = false; probe.running = true }
    }
    Process {
        command: ["pactl", "subscribe"]
        environment: root.processEnvironment
        running: Pipewire.ready
        onStarted: root.refresh()
        stdout: SplitParser { onRead: line => { if (/on (sink|card|server) #/.test(line)) root.refresh() } }
    }
    Process {
        id: probe
        command: ["pactl", "--format=json", "list", "sinks"]
        onRunningChanged: if (!running && root.refreshPending) root.refresh()
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.sinks = JSON.parse(text) } catch (error) { root.sinks = [] }
        } }
    }
}

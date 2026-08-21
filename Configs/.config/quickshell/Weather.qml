pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var output: ({ text: "", tooltip: "" })
    property var data: ({})

    function refresh() { if (!process.running) process.running = true }
    function minMax() {
        const match = String(output.tooltip || "").match(/Max\|Min:\s*([^\n<]+)/)
        return match ? match[1] : ""
    }

    FileView {
        id: cache
        path: Quickshell.env("HOME") + "/.cache/wttr/weather_data.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.data = JSON.parse(text()) }
            catch (error) { console.warn("weather cache: " + error) }
        }
    }
    Process {
        id: process
        command: ["hyprshell", "weather", "--alt"]
        stdout: SplitParser { onRead: line => {
            try { root.output = JSON.parse(line) }
            catch (error) { console.warn("weather: " + error) }
        } }
        onExited: cache.reload()
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var output: ({ text: "", tooltip: "" })
    property var data: ({})

    property var prefs: ({})

    function refresh() { if (!process.running) process.running = true }
    function readouts() { return Array.isArray(prefs.readouts) ? prefs.readouts : ["temp"] }
    function savePrefs(changes) {
        prefs = Object.assign({}, prefs, changes)
        prefsFile.setText(JSON.stringify(prefs))
    }

    FileView {
        id: prefsFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/weather.json"
        printErrors: false
        onLoaded: {
            try { root.prefs = JSON.parse(text()) }
            catch (error) { root.prefs = ({}) }
        }
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

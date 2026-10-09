pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var output: ({ text: "", tooltip: "" })
    property var data: ({})

    readonly property int likelyRainChance: 70
    readonly property int rainLookaheadHours: 3
    readonly property int hourMs: 3600000
    property bool rainNoticeSent: false
    readonly property var likelyRainHour: {
        const now = Date.now()
        for (const day of data.weather ?? [])
            for (const hour of day.hourly ?? []) {
                const start = Date.parse(hour.time)
                if (start + hourMs > now && start < now + rainLookaheadHours * hourMs && Number(hour.chanceofrain) >= likelyRainChance)
                    return hour
            }
        return null
    }
    onLikelyRainHourChanged: {
        if (!likelyRainHour) {
            rainNoticeSent = false
        } else if (!rainNoticeSent) {
            rainNoticeSent = true
            Quickshell.execDetached(["notify-send", "-a", "Weather", "-i", "weather-showers",
                "Rain likely around " + likelyRainHour.time.split("T")[1], likelyRainHour.chanceofrain + "% chance of rain"])
        }
    }

    property var prefs: ({})
    readonly property bool imperial: "imperial" in prefs ? prefs.imperial === true : localeImperial
    readonly property bool localeImperial: {
        const country = String(data.nearest_area?.[0]?.country?.[0]?.value ?? "").toLowerCase()
        if (country) return ["us", "usa", "united states", "united states of america", "liberia", "myanmar", "burma"].includes(country)
        const locale = String(Qt.locale().name).replace(".", "_")
        return /^en[_-]US($|[_.-])/.test(locale) || /^en[_-]LR($|[_.-])/.test(locale) || /^my($|[_.-])/.test(locale)
    }

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

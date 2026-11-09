import QtQuick
import Quickshell
import Quickshell.Io
import "Units.js" as Units

Scope {
    id: root
    required property var shell
    readonly property int defaultIntervalMinutes: 60
    property bool loaded: false
    property bool enabled: false
    property int intervalMinutes: defaultIntervalMinutes
    property string order: "next"
    property double lastChangeEpoch: 0
    property string seenTheme: ""
    readonly property string themeName: shell.themeName
    readonly property double dueEpoch: lastChangeEpoch + intervalMinutes * Units.MS_PER_MINUTE
    readonly property string statusText: enabled ? "Next theme at " + Qt.formatTime(new Date(dueEpoch), "HH:mm") : "Theme rotation paused"

    function applyConfig(raw) {
        let parsed = {}
        try { parsed = raw.trim() ? JSON.parse(raw) : {} }
        catch (error) { console.warn("theme-rotation.json: " + error) }
        root.enabled = parsed.enabled === true
        root.intervalMinutes = Wallpaper.intervalSteps.includes(parsed.intervalMinutes) ? parsed.intervalMinutes : root.defaultIntervalMinutes
        root.order = parsed.order === "random" ? "random" : "next"
        root.lastChangeEpoch = Number(parsed.lastChangeEpoch) || Date.now()
        root.loaded = true
        rotationTimer.stop()
        if (!root.enabled) return
        rotationTimer.interval = Math.max(1, root.dueEpoch - Date.now())
        rotationTimer.start()
    }
    function save(patch) {
        const text = JSON.stringify(Object.assign({enabled: root.enabled, intervalMinutes: root.intervalMinutes,
            order: root.order, lastChangeEpoch: root.lastChangeEpoch}, patch), null, 2) + "\n"
        configFile.setText(text)
        root.applyConfig(text)
    }
    function setEnabled(value) { root.save({enabled: value, lastChangeEpoch: Date.now()}) }
    function rotate() {
        root.shell.run([root.shell.home + "/.local/lib/hypr/theme/theme.switch.sh", "--rotate", root.order, "--quiet"])
        root.save({lastChangeEpoch: Date.now()})
    }
    onThemeNameChanged: {
        if (root.seenTheme && root.loaded) root.save({lastChangeEpoch: Date.now()})
        root.seenTheme = root.themeName
    }

    FileView {
        id: configFile
        path: root.shell.home + "/.local/state/quickshell/theme-rotation.json"
        printErrors: false
        atomicWrites: true
        onLoaded: root.applyConfig(text())
        onLoadFailed: root.applyConfig("")
    }
    Timer { id: rotationTimer; onTriggered: root.rotate() }
}

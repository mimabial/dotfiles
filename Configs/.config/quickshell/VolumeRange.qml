import QtQuick
import Quickshell.Io

Item {
    id: root
    required property string home
    readonly property real cubicVolumeDbPerDecade: 60
    property real limit: 1
    property real minDb: -60
    property real maxDb: 0
    property real stepDb: 1

    function toDb(volume) { return cubicVolumeDbPerDecade * Math.log10(volume) }
    function fromDb(db) { return Math.pow(10, db / cubicVolumeDbPerDecade) }
    function setLimit(volume, persist) {
        limit = Math.max(fromDb(minDb), Math.min(fromDb(maxDb), volume))
        if (persist) limitFile.setText(limit.toFixed(6) + "\n")
    }
    function refresh() { if (!rangeProbe.running) rangeProbe.running = true }
    function loadRange(raw) {
        try {
            const range = JSON.parse(raw)
            const minimum = Number(range.minimum), maximum = Number(range.maximum), step = Number(range.step)
            if (!isFinite(minimum) || !isFinite(maximum) || !isFinite(step) || minimum >= maximum || step <= 0) return
            minDb = minimum; maxDb = maximum; stepDb = step
            setLimit(limit, true)
        } catch (error) {}
    }

    FileView { id: limitFile; path: root.home + "/.local/state/quickshell/volume-limit"; printErrors: false; onLoaded: { const value = Number(text()); if (value > 0) root.setLimit(value, false) } }
    Process { id: rangeProbe; command: [root.home + "/.local/lib/hypr/controls/volume-control.sh", "--limits"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadRange(text) } }
}

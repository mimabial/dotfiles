import QtQuick
import Quickshell.Io
import "Units.js" as Units

Item {
    id: root
    required property string home
    property var items: []
    property double nowMs: Date.now()
    readonly property int now: Math.floor(nowMs / Units.MS_PER_SECOND)
    readonly property var entries: items.filter(item => Number(item.epoch) > now).sort((a, b) => a.epoch - b.epoch)
    readonly property var timers: entries.filter(item => item.kind === "timer")

    function load(raw) { try { items = JSON.parse(raw) || [] } catch (error) { items = [] } }
    function refresh() { stateFile.reload() }

    FileView { id: stateFile; path: root.home + "/.local/state/quickshell/timers.json"; watchChanges: true; printErrors: false; onLoaded: root.load(text()); onFileChanged: reload() }
    Timer { interval: Units.MS_PER_SECOND; repeat: true; running: root.entries.length > 0; triggeredOnStart: true; onTriggered: root.nowMs = Date.now() }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "../js/Schema.js" as Schema

Item {
    id: root
    visible: false
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/altscape"
    property var values: ({})
    property bool loaded: false
    property bool dirReady: false
    property bool dirty: false
    property bool saving: false

    function set(key, value) {
        if (values[key] === value) return
        const next = Object.assign({}, values)
        if (value === null || value === undefined) delete next[key]
        else next[key] = value
        values = next
        dirty = true
        flush()
    }
    function resetAll(defaults) {
        values = Object.assign({}, defaults)
        dirty = true
        flush()
    }
    function flush() {
        if (!dirty || saving || !loaded || !dirReady) return
        const text = JSON.stringify(values, null, 2) + "\n"
        if (text === file.text()) { dirty = false; return }
        saving = true
        dirty = false
        file.setText(text)
    }
    function absorb(text) {
        if (loaded) return
        let saved = {}
        try { saved = JSON.parse(text || "{}") }
        catch (error) { console.warn("Altscape settings: " + error) }
        const next = Object.assign({}, saved, values)
        values = Schema.migrate(next)
        dirty = dirty || JSON.stringify(values) !== JSON.stringify(next)
        loaded = true
        flush()
    }
    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
        onExited: code => {
            root.dirReady = code === 0
            if (code !== 0) console.warn("Altscape: could not create settings directory")
        }
    }
    FileView {
        id: file
        path: root.dirReady ? root.stateDir + "/settings.json" : ""
        printErrors: false
        onLoaded: Qt.callLater(root.absorb, text())
        onLoadFailed: if (root.dirReady) Qt.callLater(root.absorb, "{}")
        onSaved: { root.saving = false; Qt.callLater(root.flush) }
        onSaveFailed: error => {
            root.saving = false
            root.dirty = true
            console.warn("Altscape settings could not be saved: " + error)
        }
    }
}

import QtQml
import Quickshell.Io

QtObject {
    id: root
    required property string home
    property string layout: "main"
    property var theme: ({ rounding: 0, palette: {} })
    property var baseRules: ({})
    property var overrides: ({})
    readonly property var rules: merge(baseRules, overrides)

    readonly property var palette: theme.palette || ({})
    readonly property real radius: theme.rounding || 0
    readonly property var fallback: ({
        margin: [0, 0, 0, 0], padding: [0, 0, 0, 0],
        fontSize: 16, fontWeight: 400, border: 0, minWidth: 0, minHeight: 0,
        justify: "center"
    })

    function box(name) { const key = String(name || ""), base = key.endsWith(".active") && rules[key.slice(0, -7)]; return base ? merge(base, rules[key] || {}) : rules[key] || rules[""] || fallback }
    function merge(base, over) {
        const out = Object.assign({}, base)
        for (const key in over) out[key] = out[key] && over[key] && typeof out[key] === "object" && typeof over[key] === "object" && !Array.isArray(out[key]) && !Array.isArray(over[key]) ? merge(out[key], over[key]) : over[key]
        return out
    }

    property FileView themeFile: FileView {
        path: root.home + "/.cache/hypr/render/quickshell/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.theme = JSON.parse(text()) }
            catch (error) { console.warn("theme.json: " + error) }
        }
    }
    property FileView baseStyleFile: FileView {
        path: root.home + "/.config/quickshell/styles/base.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.baseRules = JSON.parse(text()) }
            catch (error) { console.warn("style base: " + error) }
        }
    }
    property FileView styleFile: FileView {
        path: root.home + "/.config/quickshell/styles/" + root.layout + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.overrides = JSON.parse(text()) }
            catch (error) { console.warn("style " + root.layout + ": " + error) }
        }
    }
}

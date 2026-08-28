import QtQml
import Quickshell.Io

QtObject {
    id: root
    required property string home
    property string layout: "main"
    property var theme: ({ rounding: 0, palette: {} })
    property var baseRules: ({})
    property var overrides: ({})
    readonly property var rules: resolve(baseRules, overrides)

    readonly property var palette: theme.palette || ({})
    readonly property real radius: theme.rounding || 0
    readonly property var fallback: ({
        margin: [0, 0, 0, 0], padding: [0, 0, 0, 0],
        fontSize: 16, fontWeight: 400, border: 0, minWidth: 0, minHeight: 0,
        justify: "center"
    })

    // a rule inherits its dotted parent then the "" root, so a file states only
    // what it changes; the chain is flattened once per load, never per lookup.
    // the layout's own "" lands above every base rule, so it overrides rather
    // than being buried under them: fallback < base"" < base[key] < over"" < over[key]
    function box(name) { const key = String(name || ""); return rules[key] || (key.includes(".") ? box(key.slice(0, key.lastIndexOf("."))) : rules[""] || fallback) }
    function resolve(base, over) {
        const out = {}, root = merge(fallback, base[""] || {})
        const build = key => key in out ? out[key] : (out[key] = merge(merge(merge(
            key.includes(".") ? build(key.slice(0, key.lastIndexOf("."))) : root,
            base[key] || {}), over[""] || {}), over[key] || {}))
        for (const key in base) build(key)
        for (const key in over) build(key)
        return out
    }
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

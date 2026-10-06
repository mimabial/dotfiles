import QtQml
import Quickshell.Io

QtObject {
    id: root
    required property string home
    property string styleName: "horizontal"
    property string variant: ""
    property var theme: ({ rounding: 0, borderSize: 0, palette: {} })
    property var baseRules: ({})
    property var overrides: ({})
    readonly property var rules: resolveRules(baseRules, variant ? mergeRules(overrides, overrides[variant] ?? {}) : overrides)
    property string loadedStyle: ""
    readonly property bool ready: loadedStyle === styleName

    readonly property var palette: theme.palette || ({})
    readonly property real radius: theme.rounding || 0
    readonly property real border: theme.borderSize || 0
    readonly property var fallback: ({
        margin: [0, 0, 0, 0], padding: [0, 0, 0, 0],
        fontSize: 12, fontWeight: 400, borderWidth: 0, minWidth: 0, minHeight: 0,
        justify: "center"
    })

    function box(name) {
        const selector = String(name || "")
        if (rules[selector]) return rules[selector]
        const parentEnd = selector.lastIndexOf(".")
        return parentEnd >= 0 ? box(selector.slice(0, parentEnd)) : rules[""] || fallback
    }
    function resolveRules(baseGroups, styleGroups) {
        const baseRulesBySelector = expandGroupedRules(baseGroups)
        const styleRulesBySelector = expandGroupedRules(styleGroups)
        const resolvedRules = {}
        const rootBaseRule = mergeRules(fallback, baseRulesBySelector[""] || {})
        const rootStyleRule = styleRulesBySelector[""] || {}
        const resolveSelector = selector => {
            if (selector in resolvedRules) return resolvedRules[selector]
            const parentEnd = selector.lastIndexOf(".")
            const inheritedRule = parentEnd >= 0 ? resolveSelector(selector.slice(0, parentEnd)) : rootBaseRule
            const baseRule = baseRulesBySelector[selector] || {}
            const matchingStyleDefaults = parentEnd >= 0 ? matchingFields(rootStyleRule, baseRule) : rootStyleRule
            const ruleWithBase = mergeRules(inheritedRule, baseRule)
            const ruleWithStyleDefaults = mergeRules(ruleWithBase, matchingStyleDefaults)
            resolvedRules[selector] = mergeRules(ruleWithStyleDefaults, styleRulesBySelector[selector] || {})
            return resolvedRules[selector]
        }
        for (const layer of [baseRulesBySelector, styleRulesBySelector])
            for (const selector in layer) resolveSelector(selector)
        return resolvedRules
    }
    function expandGroupedRules(groups) {
        const expandedRules = {}
        for (const group in groups)
            for (const selector of group.split(",").map(name => name.trim()))
                expandedRules[selector] = mergeRules(expandedRules[selector] || {}, groups[group])
        return expandedRules
    }
    function mergeableObjects(first, second) {
        return first && second && typeof first === "object" && typeof second === "object"
            && !Array.isArray(first) && !Array.isArray(second)
    }
    function matchingFields(styleRule, baseRule) {
        const matching = {}
        for (const key in baseRule) {
            if (!(key in styleRule)) continue
            matching[key] = mergeableObjects(styleRule[key], baseRule[key])
                ? matchingFields(styleRule[key], baseRule[key]) : styleRule[key]
        }
        return matching
    }
    function mergeRules(baseRule, overrideRule) {
        const merged = Object.assign({}, baseRule)
        for (const key in overrideRule)
            merged[key] = mergeableObjects(merged[key], overrideRule[key])
                ? mergeRules(merged[key], overrideRule[key]) : overrideRule[key]
        return merged
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
        path: root.home + "/.config/quickshell/styles/" + root.styleName + ".json"
        watchChanges: true
        printErrors: false
        onPathChanged: { root.overrides = ({}); reload() }
        onFileChanged: reload()
        onLoadFailed: root.loadedStyle = root.styleName
        onLoaded: {
            try { root.overrides = JSON.parse(text()) }
            catch (error) { console.warn("style " + root.styleName + ": " + error) }
            root.loadedStyle = root.styleName
        }
    }
}

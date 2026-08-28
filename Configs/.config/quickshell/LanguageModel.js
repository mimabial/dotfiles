function unquote(value) {
    return String(value || "").trim().replace(/^['\"]|['\"]$/g, "")
}

function parseCatalog(text) {
    var layouts = []
    var shortcuts = []
    var section = ""
    var entry = null
    var group = ""

    String(text || "").split("\n").forEach(function(line) {
        if (line === "layouts:") {
            section = "layouts"
            entry = null
            return
        }
        if (line === "option_groups:") {
            section = "options"
            entry = null
            return
        }
        if (section === "layouts") {
            var layoutStart = line.match(/^- layout:\s*(.*)$/)
            if (layoutStart) {
                entry = {layout: unquote(layoutStart[1]), variant: "", brief: "", description: ""}
                layouts.push(entry)
                return
            }
            var field = line.match(/^  (variant|brief|description):\s*(.*)$/)
            if (entry && field) entry[field[1]] = unquote(field[2])
            return
        }
        if (section !== "options") return
        var groupStart = line.match(/^- name:\s*(.*)$/)
        if (groupStart) {
            group = unquote(groupStart[1])
            return
        }
        if (group !== "grp") return
        var optionStart = line.match(/^  - name:\s*(.*)$/)
        if (optionStart) {
            entry = {value: unquote(optionStart[1]), label: ""}
            shortcuts.push(entry)
            return
        }
        var description = line.match(/^    description:\s*(.*)$/)
        if (entry && description) entry.label = unquote(description[1])
    })

    return {
        layouts: layouts.filter(function(item) { return item.layout && item.description }),
        shortcuts: shortcuts.filter(function(item) {
            return /^grp:/.test(item.value)
                && !/_switch(?:_|$)/.test(item.value)
                && (/_toggle(?:_|$)/.test(item.value) || /_select$/.test(item.value) || item.value === "grp:toggle")
                && item.label
        })
    }
}

function normalizeLayouts(value) {
    if (!Array.isArray(value)) return []
    return value.filter(function(item) {
        return item && /^[A-Za-z0-9_+-]+$/.test(String(item.layout || ""))
            && /^[A-Za-z0-9_+-]*$/.test(String(item.variant || ""))
    }).map(function(item) {
        return {layout: String(item.layout), variant: String(item.variant || "")}
    })
}

function findCatalogEntry(catalog, layout, variant) {
    var entries = catalog && Array.isArray(catalog.layouts) ? catalog.layouts : []
    return entries.find(function(item) {
        return item.layout === layout && item.variant === String(variant || "")
    }) || null
}

function descriptionFor(catalog, layout, variant) {
    var item = findCatalogEntry(catalog, layout, variant)
    return item ? item.description : String(layout || "").toUpperCase() + (variant ? " (" + variant + ")" : "")
}

function labelFor(catalog, layout, variant) {
    var item = findCatalogEntry(catalog, layout, variant)
    var raw = item && item.brief ? item.brief.split("-")[0] : String(layout || "")
    raw = raw.replace(/[^A-Za-z]/g, "").toUpperCase()
    return (raw + String(layout || "XX").toUpperCase() + "XX").substring(0, 2)
}

function configuredKey(layout, variant) {
    return String(layout || "") + "\u0000" + String(variant || "")
}

function unusedLayoutOptions(catalog, configured) {
    var used = {}
    normalizeLayouts(configured).forEach(function(item) {
        used[configuredKey(item.layout, item.variant)] = true
    })
    var entries = catalog && Array.isArray(catalog.layouts) ? catalog.layouts : []
    return entries.filter(function(item) {
        return !used[configuredKey(item.layout, item.variant)]
    }).map(function(item) {
        return {
            layout: item.layout,
            variant: item.variant,
            label: item.description,
            description: item.layout.toUpperCase() + (item.variant ? " · " + item.variant : " · default")
        }
    })
}

function shortcutOptions(catalog) {
    var options = [{value: "", label: "No shortcut", description: "Switch from the bar or another binding"}]
    var entries = catalog && Array.isArray(catalog.shortcuts) ? catalog.shortcuts : []
    return options.concat(entries.map(function(item) {
        return {value: item.value, label: item.label, description: item.value}
    }))
}

function shortcutLabel(catalog, value) {
    if (!value) return "No keyboard shortcut"
    var entries = catalog && Array.isArray(catalog.shortcuts) ? catalog.shortcuts : []
    var item = entries.find(function(candidate) { return candidate.value === value })
    return item ? item.label : value
}

function filterOptions(options, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (!needle) return options || []
    return (options || []).filter(function(item) {
        return [item.label, item.description, item.value, item.layout, item.variant]
            .map(function(value) { return String(value || "").toLowerCase() })
            .some(function(value) { return value.indexOf(needle) !== -1 })
    })
}

if (typeof module !== "undefined") module.exports = {
    descriptionFor: descriptionFor,
    filterOptions: filterOptions,
    labelFor: labelFor,
    normalizeLayouts: normalizeLayouts,
    parseCatalog: parseCatalog,
    shortcutLabel: shortcutLabel,
    shortcutOptions: shortcutOptions,
    unusedLayoutOptions: unusedLayoutOptions
}

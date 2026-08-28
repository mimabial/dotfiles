.pragma library

// Renders the managed block the panel writes, then parses the reader records,
// theme variables, and `hyprctl -j --batch getoption` output it reads back.
//
// The rendered string is the same one handed to `hyprctl eval` for the live
// preview, so preview and saved state cannot drift. Keep it that way: a second
// renderer anywhere is a second grammar.

var BEGIN_FENCE = "-- >>> look and feel (generated; edit in the panel) >>>"
var END_FENCE = "-- <<< look and feel <<<"

// ------------------------------------------------------------- rendering

function indent(depth) {
    var pad = ""
    for (var i = 0; i < depth; i++) pad += "    "
    return pad
}

function renderValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") return String(value)
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

// Scalars before nested tables, so the generated Lua reads the way a
// hand-written config section does.
function renderTable(node, depth) {
    var scalars = []
    var nested = []
    for (var key in node) {
        if (node[key] !== null && typeof node[key] === "object") nested.push(key)
        else scalars.push(key)
    }
    var lines = []
    var i
    for (i = 0; i < scalars.length; i++)
        lines.push(indent(depth + 1) + scalars[i] + " = " + renderValue(node[scalars[i]]))
    for (i = 0; i < nested.length; i++)
        lines.push(indent(depth + 1) + nested[i] + " = " + renderTable(node[nested[i]], depth + 1))
    return "{\n" + lines.join(",\n") + "\n" + indent(depth) + "}"
}

function buildTree(overrides) {
    var root = {}
    for (var key in overrides) {
        var parts = String(key).split(":")
        var cursor = root
        for (var i = 0; i < parts.length - 1; i++) {
            if (!cursor[parts[i]] || typeof cursor[parts[i]] !== "object")
                cursor[parts[i]] = {}
            cursor = cursor[parts[i]]
        }
        cursor[parts[parts.length - 1]] = overrides[key]
    }
    return root
}

function renderAnimation(animation) {
    var parts = ['leaf = "' + animation.leaf + '"']
    parts.push("enabled = " + (animation.enabled === false ? "false" : "true"))
    if (animation.speed !== undefined && animation.speed !== null && animation.speed !== "")
        parts.push("speed = " + animation.speed)
    if (animation.bezier) parts.push('bezier = "' + animation.bezier + '"')
    if (animation.style) parts.push('style = "' + animation.style + '"')
    return "hl.animation({ " + parts.join(", ") + " })"
}

// Returns "" when there is nothing to write, which is what lets clearing the
// last override delete the file and hand the keys back to the theme layer.
function renderBlock(overrides, animations, variables) {
    var keys = []
    for (var key in (overrides || {})) keys.push(key)
    var list = animations || []
    var variableKeys = []
    for (var variable in (variables || {})) variableKeys.push(variable)
    if (keys.length === 0 && list.length === 0 && variableKeys.length === 0) return ""

    var body = []
    if (variableKeys.length > 0) {
        variableKeys.sort()
        body.push('local vars = require("vars")')
        for (var v = 0; v < variableKeys.length; v++) {
            var name = variableKeys[v]
            // Hypr's vars module stores strings, and the shared shell config
            // parser deliberately accepts only this quoted generated form.
            body.push("vars.set(" + renderValue(name) + ", "
                + renderValue(String(variables[name])) + ")")
        }
    }
    if (keys.length > 0)
        body.push("hl.config(" + renderTable(buildTree(overrides), 0) + ")")
    for (var i = 0; i < list.length; i++)
        body.push(renderAnimation(list[i]))

    return BEGIN_FENCE + "\n" + body.join("\n") + "\n" + END_FENCE + "\n"
}

// --------------------------------------------------------------- parsing

function parseRecords(text) {
    var keys = {}
    var variables = {}
    var animations = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i]) continue
        var f = lines[i].split("\t")
        if (f[0] === "k") {
            var raw = f[3]
            keys[f[1]] = f[2] === "number" ? Number(raw)
                : f[2] === "boolean" ? raw === "true"
                : raw
        } else if (f[0] === "v") {
            variables[f[1]] = f[3]
        } else if (f[0] === "a") {
            animations.push({
                leaf: f[1],
                enabled: f[2] === "true",
                speed: f[3] === "" || f[3] === undefined ? 0 : Number(f[3]),
                bezier: f[4] || "",
                style: f[5] || ""
            })
        }
    }
    return { keys: keys, variables: variables, animations: animations }
}

// Custom-type values serialize as four edge values ("7 7 7 7"). Nothing in this
// config sets them per-edge, so the first field is the value.
function cssScalar(css) {
    var first = String(css === undefined ? "" : css).trim().split(/\s+/)[0]
    var value = Number(first)
    return isNaN(value) ? 0 : value
}

// `hyprctl -j --batch` emits one chunk per command, blank-line separated, and
// does not abort on a bad key: an inactive layout engine's options come back as
// a bare `no such option` line. Skip anything that is not JSON.
function parseGetoption(text) {
    var out = {}
    var chunks = String(text || "").split(/\n\s*\n/)
    for (var i = 0; i < chunks.length; i++) {
        var chunk = chunks[i].trim()
        if (!chunk || chunk.charAt(0) !== "{") continue
        var data
        try {
            data = JSON.parse(chunk)
        } catch (error) {
            continue
        }
        if (!data || !data.option) continue

        var entry = null
        if ("int" in data) entry = { value: data.int, type: "int" }
        else if ("float" in data) entry = { value: data.float, type: "float" }
        else if ("bool" in data) entry = { value: data.bool, type: "bool" }
        else if ("str" in data) entry = { value: data.str, type: "str" }
        else if ("css" in data) entry = { value: cssScalar(data.css), type: "css" }
        if (!entry) continue

        entry.set = data.set === true
        out[data.option] = entry
    }
    return out
}

// The theme pack's own values, straight from themes/theme.lua. Unlike a
// getoption read these are not clouded by the panel's override block, so a row
// dialled back to the theme's value can be recognised as no longer overridden.
function parseThemeConfig(text) {
    var out = {}
    var rx = /runtime\.config\(\s*"([^"]+)"\s*,\s*(.+?)\s*\)\s*$/
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var match = rx.exec(lines[i].trim())
        if (!match) continue
        var value = match[2]
        if (value.charAt(0) === '"') value = value.slice(1, -1)
        else if (value === "true" || value === "false") value = value === "true"
        else if (!isNaN(Number(value))) value = Number(value)
        out[match[1].split(".").join(":")] = value
    }
    return out
}

// Theme variables need their own namespace: CURSOR_SIZE is not a Hyprland
// option and must never be mistaken for one by baseline/reset handling.
function parseThemeVariables(text) {
    var out = {}
    var rx = /vars\.set\(\s*"([^"]+)"\s*,\s*"([^"]*)"\s*\)\s*$/
    var lines = String(text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var match = rx.exec(lines[i].trim())
        if (match) out[match[1]] = match[2]
    }
    return out
}

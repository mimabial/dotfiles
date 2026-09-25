.pragma library

var TOGGLES = ["fps", "frame_timing", "gpu_stats", "gpu_temp", "cpu_stats", "cpu_temp", "vram", "ram", "gpu_name", "gamemode", "hud_compact"]
var POSITIONS = ["top-left", "top-right", "bottom-left", "bottom-right"]

function parse(raw) {
    const options = {}
    for (const line of String(raw || "").split(/\r?\n/)) {
        const match = line.match(/^\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:=\s*(.*?)\s*)?$/)
        if (match) options[match[1]] = match[2] === undefined ? "1" : match[2]
    }
    return options
}

function value(options, key, fallback) {
    return Object.prototype.hasOwnProperty.call(options, key) ? options[key] : fallback
}

function enabled(options, key) {
    return !["0", "false", "off", "no"].includes(String(value(options, key, "0")).toLowerCase())
}

function valid(key, value) {
    if (TOGGLES.includes(key)) return value === "0" || value === "1"
    if (key === "position") return POSITIONS.includes(value)
    const number = Number(value)
    if (key === "fps_limit") return /^\d+$/.test(value) && number <= 360
    if (key === "font_size") return /^\d+$/.test(value) && number >= 10 && number <= 48
    if (key === "background_alpha") return /^\d+(?:\.\d+)?$/.test(value) && number >= 0 && number <= 1
    return false
}

function update(raw, key, value) {
    const next = String(value)
    if (!valid(key, next)) return String(raw || "")
    const lines = String(raw || "").split(/\r?\n/)
    if (lines.length && lines[lines.length - 1] === "") lines.pop()
    const output = []
    let written = false
    for (const line of lines) {
        const match = line.match(/^\s*([A-Za-z][A-Za-z0-9_]*)\s*(?:=.*)?$/)
        if (match && match[1] === key) {
            if (!written) output.push(key + "=" + next)
            written = true
        } else output.push(line)
    }
    if (!written) output.push(key + "=" + next)
    return output.join("\n") + "\n"
}

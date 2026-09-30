.pragma library

var presets = [
    { name: "Opaque", value: 1 },
    { name: "Glass", value: 0.8 },
    { name: "Frosted Glass", value: 0.65 },
    { name: "Translucent", value: 0.35 },
    { name: "Transparent", value: 0 }
]

function label(preset) { return `${preset.name} (${Math.round(preset.value * 100)}%)` }

function nearest(value) {
    return presets.reduce((best, preset) => Math.abs(preset.value - value) < Math.abs(best.value - value) ? preset : best)
}

function presetId(value) { return value < 0 ? "auto" : String(Math.round(nearest(value).value * 100)) }

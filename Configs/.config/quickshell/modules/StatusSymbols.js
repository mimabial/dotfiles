.pragma library

// freedesktop status icon names for the modules that draw SymbolicIcons

function level(fraction, names) {
    return names[Math.max(0, Math.min(names.length - 1, Math.floor(fraction * names.length)))]
}

function battery(device, onBattery) {
    const percent = Math.round(device.percentage * 10) * 10
    return "battery-level-" + (onBattery ? percent : percent === 100 ? "100-charged" : percent + "-charging")
}

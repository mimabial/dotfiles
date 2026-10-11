.pragma library


function level(fraction, names) {
    return names[Math.max(0, Math.min(names.length - 1, Math.floor(fraction * names.length)))]
}

function wifi(enabled, connectedNetwork) {
    return !enabled ? "network-wireless-disabled" : !connectedNetwork ? "network-wireless-offline"
        : "network-wireless-signal-" + level(connectedNetwork.signalStrength, ["none", "weak", "ok", "good", "excellent"])
}

function volume(node, muted, prefix = "audio-volume") {
    const volume = node?.audio?.volume ?? 0
    return prefix + "-" + (!node || muted ? "muted" : prefix === "audio-volume" && volume > 1 ? "overamplified"
        : level(volume, ["low", "medium", "high"]))
}

function brightness(fraction) {
    return "display-brightness-" + (fraction === 0 ? "off" : level(fraction, ["low", "medium", "high"]))
}

function battery(device, onBattery) {
    const percent = Math.round(device.percentage * 10) * 10
    return "battery-level-" + (onBattery ? percent : percent === 100 ? "100-charged" : percent + "-charging")
}

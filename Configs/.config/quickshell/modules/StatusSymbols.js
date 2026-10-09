.pragma library


function level(fraction, names) {
    return names[Math.max(0, Math.min(names.length - 1, Math.floor(fraction * names.length)))]
}

function wifi(enabled, connectedNetwork) {
    return !enabled ? "network-wireless-disabled" : !connectedNetwork ? "network-wireless-offline"
        : "network-wireless-signal-" + level(connectedNetwork.signalStrength, ["none", "weak", "ok", "good", "excellent"])
}

function volume(sink, muted) {
    const volume = sink?.audio?.volume ?? 0
    return !sink || muted ? "audio-volume-muted" : volume < .34 ? "audio-volume-low" : volume < .67 ? "audio-volume-medium" : "audio-volume-high"
}

function battery(device, onBattery) {
    const percent = Math.round(device.percentage * 10) * 10
    return "battery-level-" + (onBattery ? percent : percent === 100 ? "100-charged" : percent + "-charging")
}

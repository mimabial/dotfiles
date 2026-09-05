// Bluetooth device, PipeWire endpoint, and audio-profile projections.

function toArray(values) {
    if (!values) return []
    if (Array.isArray(values)) return values.slice()
    var result = []
    for (var i = 0; i < Number(values.length || 0); i++) result.push(values[i])
    return result
}

function normalizedAddress(value) {
    var text = String(value || "").trim().toLowerCase()
    if (/^[0-9a-f]{12}$/.test(text)) return text
    return /^[0-9a-f]{2}(?:[:_-][0-9a-f]{2}){5}$/.test(text)
        ? text.replace(/[:_-]/g, "") : ""
}

function isUuidLike(value) {
    var text = String(value || "").trim()
    return /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(text)
        || /^[0-9a-f]{32}$/i.test(text) || /^0x[0-9a-f]{4,32}$/i.test(text)
}

function deviceLabel(device) {
    return device ? String(device.name || device.deviceName || device.address || "").trim() : ""
}

function hasHumanName(device) {
    var values = device ? [device.name, device.deviceName] : []
    for (var i = 0; i < values.length; i++) {
        var value = String(values[i] || "").trim()
        if (value && !isUuidLike(value) && !normalizedAddress(value)) return true
    }
    return false
}

function sortedByLabel(devices) {
    var values = toArray(devices)
    values.sort(function(left, right) { return deviceLabel(left).localeCompare(deviceLabel(right)) })
    return values
}

function deviceLists(devices) {
    var groups = { connected: [], known: [], discovered: [] }
    var values = toArray(devices)
    for (var i = 0; i < values.length; i++) {
        var device = values[i]
        if (!device || !hasHumanName(device) && !device.connected && !device.paired
                && !device.bonded && !device.trusted && !device.blocked) continue
        if (device.connected) groups.connected.push(device)
        else if (device.paired || device.bonded || device.trusted || device.blocked)
            groups.known.push(device)
        else groups.discovered.push(device)
    }
    groups.connected = sortedByLabel(groups.connected)
    groups.known = sortedByLabel(groups.known)
    groups.discovered = sortedByLabel(groups.discovered)
    return groups
}

// Delegates keep primitives so a discovery removal cannot leave a dangling
// BlueZ QObject behind while Quickshell is still incubating the row.
function deviceRow(device) {
    if (!device) return null
    return {
        address: device.address || "", dbusPath: device.dbusPath || "",
        name: device.name || "", deviceName: device.deviceName || "",
        icon: device.icon || "", connected: !!device.connected,
        state: device.state !== undefined ? device.state : -1,
        paired: !!device.paired, bonded: !!device.bonded, trusted: !!device.trusted,
        blocked: !!device.blocked, wakeAllowed: !!device.wakeAllowed,
        batteryAvailable: !!device.batteryAvailable,
        battery: device.battery !== undefined ? device.battery : 0,
        pairing: !!device.pairing
    }
}

function cloneMap(values) {
    var result = {}
    for (var key in values || {}) result[key] = values[key]
    return result
}

function textContainsAddress(value, address) {
    var expected = normalizedAddress(address)
    if (!expected) return false
    var text = String(value || "").replace(
        /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig, " ")
    var matcher = /(^|[^0-9a-f])([0-9a-f]{12}|[0-9a-f]{2}(?:[:_-][0-9a-f]{2}){5})(?=$|[^0-9a-f])/ig
    var match
    while ((match = matcher.exec(text)) !== null)
        if (normalizedAddress(match[2]) === expected) return true
    return false
}

function textContainsAnyAddress(value) {
    var text = String(value || "").replace(
        /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig, " ")
    return /(^|[^0-9a-f])([0-9a-f]{12}|[0-9a-f]{2}(?:[:_-][0-9a-f]{2}){5})(?=$|[^0-9a-f])/i.test(text)
}

function normalizedIdentity(value) {
    return String(value || "").trim().toLowerCase()
        .replace(/[\x00-\x2f\x3a-\x40\x5b-\x60\x7b-\x7f]+/g, " ").trim()
}

function nodeProperties(node) {
    return node && node.ready && node.properties ? node.properties : {}
}

function isAudioSource(node) {
    if (!node || node.isSink || node.isStream || !node.audio || /\.monitor$/i.test(String(node.name || ""))) return false
    return String(nodeProperties(node)["media.class"] || "") !== "Audio/Sink"
}

function bluetoothNodeMatchesDevice(node, device, direction, peers) {
    if (!node || node.isStream || !device) return false
    if (direction === "sink" && !node.isSink || direction === "source" && !isAudioSource(node)) return false
    var props = nodeProperties(node)
    var fields = [node.name, node.description, node.nickname, node.nick,
        props["node.name"], props["node.description"], props["node.nick"],
        props["device.name"], props["device.description"], props["device.product.name"],
        props["device.alias"], props["device.string"], props["api.bluez5.address"],
        props["bluez5.address"], props["media.name"]]
    var carriesAddress = false
    for (var i = 0; i < fields.length; i++) {
        if (isUuidLike(fields[i])) continue
        if (textContainsAddress(fields[i], device.address)) return true
        if (textContainsAnyAddress(fields[i])) carriesAddress = true
    }
    if (carriesAddress) return false

    var labels = [normalizedIdentity(device.name), normalizedIdentity(device.deviceName)]
    var devices = toArray(peers)
    for (var l = 0; l < labels.length; l++) {
        var label = labels[l]
        if (!label) continue
        var ambiguous = false
        for (var p = 0; p < devices.length; p++) {
            var peer = devices[p]
            if (!peer || normalizedAddress(peer.address) === normalizedAddress(device.address)) continue
            if (normalizedIdentity(peer.name) === label || normalizedIdentity(peer.deviceName) === label) {
                ambiguous = true; break
            }
        }
        if (!ambiguous)
            for (var f = 0; f < fields.length; f++)
                if (normalizedIdentity(fields[f]) === label) return true
    }
    return false
}

function bluetoothSinkMatchesDevice(node, device, peers) {
    return bluetoothNodeMatchesDevice(node, device, "sink", peers)
}

function bluetoothSourceMatchesDevice(node, device, peers) {
    return bluetoothNodeMatchesDevice(node, device, "source", peers)
}

function sameAudioNode(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    if (left.id !== undefined && right.id !== undefined && String(left.id) === String(right.id)) return true
    return String(left.name || "") !== "" && String(left.name) === String(right.name || "")
}

function audioProfileState(states, address) {
    var state = states ? states[normalizedAddress(address)] : null
    return state && typeof state === "object" ? state : null
}

function audioProfileOptions(state) {
    var result = []
    var profiles = state && Array.isArray(state.profiles) ? state.profiles : []
    for (var i = 0; i < profiles.length; i++) {
        var value = String(profiles[i] ? profiles[i].value || profiles[i].name || "" : "")
        if (value) result.push({ value: value, label: String(profiles[i].label || value) })
    }
    return result
}

function audioProfileCodec(state, profileName) {
    var profiles = state && Array.isArray(state.profiles) ? state.profiles : []
    var name = String(profileName || (state ? state.activeProfile : "") || "")
    for (var i = 0; i < profiles.length; i++)
        if (profiles[i] && String(profiles[i].value || "") === name) return String(profiles[i].codec || "")
    return state && name === String(state.activeProfile || "") ? String(state.activeCodec || "") : ""
}

function audioProfileHasInput(state, profileName) {
    var profiles = state && Array.isArray(state.profiles) ? state.profiles : []
    var name = String(profileName || (state ? state.activeProfile : "") || "")
    for (var i = 0; i < profiles.length; i++)
        if (profiles[i] && String(profiles[i].value || "") === name)
            return profiles[i].hasInput === true || Number(profiles[i].sources || 0) > 0
    return false
}

function duplexProfileOption(state) {
    var profiles = state && Array.isArray(state.profiles) ? state.profiles : []
    for (var i = 0; i < profiles.length; i++)
        if (profiles[i] && (profiles[i].hasInput === true || Number(profiles[i].sources || 0) > 0))
            return { value: String(profiles[i].value || ""), label: String(profiles[i].label || profiles[i].value || "") }
    return null
}

function isAudioDevice(iconName, name) {
    var text = (String(iconName || "") + " " + String(name || "")).toLowerCase()
    return /audio|headset|headphone|earbud|earphone|airpod|buds|speaker|soundbar|momentum/.test(text)
}

function deviceIconGlyph(iconName, name, connected) {
    var text = (String(iconName || "") + " " + String(name || "")).toLowerCase()
    if (/headset|headphone|earbud|earphone|airpod|buds|momentum/.test(text)) return "󰋋"
    if (/video-display|\btv\b|monitor|display|googletv|mitv/.test(text)) return "󰍹"
    if (/speaker|audio-card|soundbar|audio/.test(text)) return "󰓃"
    if (/keyboard|keychron/.test(text)) return "󰌌"
    if (/mouse|trackball/.test(text)) return "󰍽"
    if (/gaming|gamepad|joystick|controller|dualsense|xbox/.test(text)) return "󰊴"
    if (/tablet|touchpad/.test(text)) return "󰓶"
    if (/phone|smartphone|telephony|iphone|galaxy s|pixel/.test(text)) return "󰏲"
    if (/computer|laptop|desktop|macbook|thinkpad/.test(text)) return "󰌢"
    if (/camera|webcam/.test(text)) return "󰄀"
    if (/watch|wearable/.test(text)) return "󰖉"
    if (/printer/.test(text)) return "󰐪"
    if (/scanner/.test(text)) return "󰚫"
    return connected ? "󰂱" : "󰂯"
}

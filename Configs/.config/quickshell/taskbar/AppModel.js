.pragma library

function identity(window) {
    return String(window.appId || window.cls || "")
}

function recordsFor(windows) {
    const byKey = Object.create(null)
    for (const window of windows) {
        const id = identity(window)
        if (id && !(id.toLowerCase() in byKey)) byKey[id.toLowerCase()] = id
    }
    return Object.keys(byKey).sort().map(key => ({ key, desktopId: byKey[key] }))
}

function windowsFor(record, windows) {
    if (!record) return []
    const id = String(record.desktopId || "").toLowerCase()
    if (!id) return []
    return windows.filter(window => identity(window).toLowerCase() === id)
}

function windowFingerprint(windows) {
    return windows.map(window => identity(window).toLowerCase()).sort().join("\u0002")
}

function sameKeys(left, right) {
    return left.length === right.length && left.every((record, index) => record.key === right[index].key)
}

function nextWindowIndex(windows, activeAddress) {
    if (!windows.length) return -1
    const index = windows.findIndex(window => window.address === activeAddress)
    return index < 0 ? 0 : (index + 1) % windows.length
}

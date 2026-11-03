.pragma library

var START_TOLERANCE = 2
var LENGTH_TOLERANCE = 4
var ON_SCREEN_FRACTION = 0.02
var LOOSE_MATCH_MIN_LENGTH = 4
var MINOR = 1
var CRITICAL = 2

var ANIM_STYLES = [
    { id: "smooth", label: "Smooth" },
    { id: "cyberpunk", label: "Cyberpunk" }
]

var MOTION = {
    smooth:    { k: 9, d: 0.7, popTo: 1.18, popOvershoot: 1.4, popIn: 120, popOut: 520, hover: 1.08, swapIn: 240 },
    cyberpunk: { k: 11, d: 1.0, popTo: 1.00, popOvershoot: 0.0, popIn: 60,  popOut: 140, hover: 1.04, swapIn: 90 }
}

function motionFor(style) { return MOTION[style] || MOTION.smooth }

function normalizeAddress(value) {
    var raw = String(value || "").trim().toLowerCase().replace(/^0x/, "")
    return /^[0-9a-f]+$/.test(raw) ? "0x" + raw : ""
}

function clientsOf(toplevels, includeFloating) {
    var clients = []
    for (var i = 0; i < toplevels.length; i++) {
        var top = toplevels[i]
        var ipc = top.lastIpcObject || {}
        var at = ipc.at, size = ipc.size
        if (!at || !size || !(size[0] > 0 && size[1] > 0) || ipc.mapped === false || ipc.hidden === true) continue
        if (ipc.floating === true && !includeFloating) continue
        clients.push({
            address: normalizeAddress(top.address || ipc.address),
            appClass: String(ipc.class || ipc.initialClass || ""),
            title: String(top.title || ipc.title || ipc.class || ""),
            floating: ipc.floating === true,
            pinned: ipc.pinned === true,
            fullscreen: Number(ipc.fullscreen) > 0,
            visible: ipc.visible === true,
            stableId: parseInt(ipc.stableId, 16),
            grouped: (ipc.grouped || []).map(normalizeAddress).filter(Boolean),
            focusHistory: isFinite(Number(ipc.focusHistoryID)) ? Number(ipc.focusHistoryID) : Infinity,
            x: at[0], y: at[1], w: size[0], h: size[1]
        })
    }
    return clients
}

function collapseGroups(clients, active) {
    var byAddress = {}
    clients.forEach(function (client) { byAddress[client.address] = client })
    var seen = {}
    var collapsed = []
    clients.forEach(function (client) {
        if (seen[client.address]) return
        var members = client.grouped.length > 1 ? client.grouped.map(function (address) { return byAddress[address] }).filter(Boolean) : []
        if (members.length < 2) {
            seen[client.address] = true
            collapsed.push(Object.assign({}, client, { tabs: null }))
            return
        }
        members.forEach(function (member) { seen[member.address] = true })
        var head = members.filter(function (member) { return member.address === active })[0]
            || members.reduce(function (best, member) { return member.focusHistory < best.focusHistory ? member : best })
        collapsed.push(Object.assign({}, head, { tabs: members.map(function (member) {
            return { address: member.address, title: member.title, appClass: member.appClass, active: member === head }
        }) }))
    })
    return collapsed
}

function groupColumns(clients) {
    var sorted = clients.slice().sort(function (a, b) { return a.x - b.x || a.y - b.y || a.stableId - b.stableId })
    var columns = []
    sorted.forEach(function (client) {
        var last = columns[columns.length - 1]
        var aligned = !!last && Math.abs(last.start - client.x) <= START_TOLERANCE && Math.abs(last.len - client.w) <= LENGTH_TOLERANCE
        var overlaid = aligned && Math.abs(last.windows[last.windows.length - 1].y - client.y) <= START_TOLERANCE
        if (aligned && !overlaid) last.windows.push(client)
        else columns.push({ start: client.x, len: client.w, windows: [client] })
    })
    return columns
}

function overlapFraction(start, end, low, high) {
    var span = end - start
    var visible = Math.min(end, high) - Math.max(start, low)
    return span > 0 && visible > 0 ? visible / span : 0
}

function buildColumns(clients, viewport, active) {
    return groupColumns(collapseGroups(clients, active)).map(function (column) {
        return {
            len: column.len,
            onScreen: overlapFraction(column.start, column.start + column.len, viewport.x, viewport.x + viewport.width) > ON_SCREEN_FRACTION
                && column.windows.some(function (window) { return window.visible }),
            windows: column.windows.map(function (window) {
                return {
                    key: window.tabs ? window.tabs.map(function (tab) { return tab.address }).sort()[0] : window.address,
                    address: window.address, title: window.title, appClass: window.appClass, tabs: window.tabs,
                    floating: window.floating, pinned: window.pinned, fullscreen: window.fullscreen,
                    off: window.y - viewport.y, span: window.h,
                    focused: window.address === active || (window.tabs || []).some(function (tab) { return tab.address === active })
                }
            })
        }
    })
}

function layoutTape(columns, scale, gap, stackGap) {
    var items = []
    var spans = []
    var cursor = 0
    columns.forEach(function (column) {
        var length = column.len * scale
        var count = column.windows.length
        column.windows.forEach(function (window, index) {
            var inStart = index > 0 ? stackGap / 2 : 0
            var inEnd = index < count - 1 ? stackGap / 2 : 0
            items.push({
                key: window.key, address: window.address,
                bx: cursor, by: window.off * scale + inStart, bw: length, bh: Math.max(1, window.span * scale - inStart - inEnd),
                focused: window.focused, onScreen: column.onScreen,
                floating: window.floating, pinned: window.pinned, fullscreen: window.fullscreen,
                tabsJson: window.tabs && window.tabs.length > 1 ? JSON.stringify(window.tabs) : ""
            })
        })
        spans.push({ start: cursor, len: length })
        cursor += length + gap
    })
    return { items: items, spans: spans, total: Math.max(0, cursor - (items.length ? gap : 0)) }
}

function windowAt(columns, address) {
    for (var i = 0; i < columns.length; i++)
        for (var j = 0; j < columns[i].windows.length; j++) {
            var window = columns[i].windows[j]
            if (window.address === address) return window
            var tab = (window.tabs || []).filter(function (tab) { return tab.address === address })[0]
            if (tab) return Object.assign({ key: window.key }, tab)
        }
    return null
}

function attentionFor(alerts, columns) {
    var attention = {}
    var other = 0
    for (var address in alerts) {
        var window = windowAt(columns, address)
        if (window) attention[window.key] = Math.max(attention[window.key] || 0, alerts[address].level)
        else other = Math.max(other, alerts[address].level)
    }
    return { attention: attention, other: other }
}

function nameTokens(value) {
    var name = String(value || "").trim().toLowerCase().replace(/\.desktop$/, "")
    var last = name.split(".").pop()
    return !name ? [] : last !== name ? [name, last] : [name]
}

function focusRank(client) { return client.focusHistory === 0 ? Number.MAX_SAFE_INTEGER : client.focusHistory }

function matchWindow(names, clients) {
    var wanted = names.reduce(function (tokens, name) { return tokens.concat(nameTokens(name)) }, [])
    var related = function (want, token) {
        return want.length >= LOOSE_MATCH_MIN_LENGTH && token.length >= LOOSE_MATCH_MIN_LENGTH && (want.indexOf(token) >= 0 || token.indexOf(want) >= 0)
    }
    var better = function (client, current) { return !current || focusRank(client) < focusRank(current) }
    var exact = null, loose = null
    clients.forEach(function (client) {
        var tokens = nameTokens(client.appClass)
        if (wanted.some(function (want) { return tokens.indexOf(want) >= 0 })) { if (better(client, exact)) exact = client }
        else if (wanted.some(function (want) { return tokens.some(function (token) { return related(want, token) }) }) && better(client, loose)) loose = client
    })
    return (exact || loose || { address: "" }).address
}

function pickAlertTarget(alerts) {
    var best = ""
    for (var address in alerts) {
        var alert = alerts[address], top = alerts[best]
        if (!top || alert.level > top.level || alert.level === top.level && alert.at > top.at) best = address
    }
    return best
}

function actionCommands(id, address, workspace) {
    var window = 'window = "address:' + address + '"'
    var focus = "hl.dsp.focus({ " + window + " })"
    switch (id) {
    case "close": return ["hl.dsp.window.close({ " + window + " })"]
    case "float": return ['hl.dsp.window.float({ action = "toggle", ' + window + " })"]
    case "fullscreen": return [focus, 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })']
    case "pin": return [focus, "hl.dsp.window.pin()"]
    case "ungroup": return [focus, "hl.dsp.group.toggle()"]
    case "moveto": return [focus, 'hl.dsp.window.move({ workspace = "' + workspace + '" })']
    }
    return []
}

function slotAt(spans, position) {
    var best = -1, bestDistance = Infinity
    spans.forEach(function (span, index) {
        var distance = Math.abs(span.start + span.len / 2 - position)
        if (distance < bestDistance) { best = index; bestDistance = distance }
    })
    return best
}

function columnSwapCommands(from, to) {
    var steps = []
    for (var i = 0; i < Math.abs(to - from); i++) steps.push('hl.dsp.layout("swapcol ' + (to > from ? "r" : "l") + '")')
    return steps
}

function swapTargetAt(items, x, y, source) {
    var hit = items.filter(function (item) {
        return item.address !== source && !item.floating
            && x >= item.bx && x < item.bx + item.bw && y >= item.by && y < item.by + item.bh
    })[0]
    return hit ? hit.address : ""
}

function windowSwapCommand(source, target) {
    return 'hl.dsp.window.swap({ window = "address:' + source + '", target = "address:' + target + '" })'
}

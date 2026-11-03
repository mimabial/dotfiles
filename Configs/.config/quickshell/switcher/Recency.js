.pragma library
.import "Depth.js" as Depth

var SEED_STEP_SECONDS = 30;

function createState() {
    return { lastActive: {}, active: "", estimated: {} };
}

function normalizeAddress(value) {
    if (value === undefined || value === null) return "";
    var text = String(value).trim().toLowerCase().replace(/^0x/, "");
    return /^[0-9a-f]+$/.test(text) && !/^0+$/.test(text) ? text : "";
}

function firstField(eventData) {
    return String(eventData === undefined || eventData === null ? "" : eventData).split(",")[0];
}

function recordFocus(state, address, nowMs) {
    var key = normalizeAddress(address);
    if (!key) return false;
    if (state.active && state.active !== key) {
        state.lastActive[state.active] = nowMs;
        if (state.estimated) delete state.estimated[state.active];
    }
    state.active = key;
    state.lastActive[key] = nowMs;
    if (state.estimated) delete state.estimated[key];
    return true;
}

function recordOpen(state, eventData, nowMs) {
    var key = normalizeAddress(firstField(eventData));
    if (!key) return false;
    if (!(key in state.lastActive))
        state.lastActive[key] = nowMs;
    return true;
}

function recordClose(state, eventData) {
    var key = normalizeAddress(firstField(eventData));
    if (!key) return false;
    delete state.lastActive[key];
    if (state.estimated) delete state.estimated[key];
    if (state.active === key) state.active = "";
    return true;
}

function seedFromClients(state, clients, nowMs, stepSeconds) {
    var step = (Number(stepSeconds) > 0 ? Number(stepSeconds) : SEED_STEP_SECONDS) * 1000;
    var list = clients && clients.length !== undefined ? clients : [];
    var seeded = 0;
    for (var i = 0; i < list.length; i++) {
        var client = list[i] || {};
        var key = normalizeAddress(client.address);
        if (!key || key in state.lastActive) continue;
        var history = Number(client.focusHistoryID);
        if (!isFinite(history) || history < 0) continue;
        state.lastActive[key] = nowMs - history * step;
        if (history === 0 && !state.active) state.active = key;
        else if (state.estimated) state.estimated[key] = true;
        seeded++;
    }
    return seeded;
}

function secondsSince(state, address, nowMs, fallbackActive) {
    var key = normalizeAddress(address);
    if (!key) return Infinity;
    var active = state.active || normalizeAddress(fallbackActive);
    if (key === active) return 0;
    var at = state.lastActive[key];
    if (at === undefined) return Infinity;
    return Math.max(0, (nowMs - at) / 1000);
}

function historyRank(value) {
    var number = Number(value);
    return isFinite(number) && number >= 0 ? number : Infinity;
}

function buildField(candidates, state, nowMs, fallbackActive) {
    var list = candidates && candidates.length !== undefined ? candidates : [];
    var activeKey = state.active || normalizeAddress(fallbackActive);
    var entries = [];
    for (var i = 0; i < list.length; i++) {
        var candidate = list[i];
        if (!candidate) continue;
        var key = normalizeAddress(candidate.address);
        if (!key) continue;
        if (candidate.hasHandle === false) continue;
        if (candidate.mapped === false) continue;

        var entry = {};
        for (var name in candidate) entry[name] = candidate[name];
        entry.address = key;
        entry.active = key === activeKey;
        entry.seconds = secondsSince(state, key, nowMs, fallbackActive);
        entry.estimated = !entry.active && (!isFinite(entry.seconds) || !!(state.estimated && state.estimated[key]));
        entries.push(entry);
    }

    entries.sort(function(a, b) {
        if (a.active !== b.active) return a.active ? -1 : 1;
        if (a.seconds !== b.seconds) return a.seconds < b.seconds ? -1 : 1;
        var ha = historyRank(a.focusHistoryID);
        var hb = historyRank(b.focusHistoryID);
        if (ha !== hb) return ha < hb ? -1 : 1;
        return a.address < b.address ? -1 : (a.address > b.address ? 1 : 0);
    });

    var oldestSeconds = Depth.oldestKnownSeconds(entries);
    for (var j = 0; j < entries.length; j++) {
        entries[j].index = j;
        entries[j].depth = Depth.depthForSeconds(entries[j].estimated ? Infinity : entries[j].seconds, oldestSeconds);
    }
    return entries;
}

function initialSelection(count, step) {
    if (count <= 0) return -1;
    if (step > 0) return count > 1 ? 1 : 0;
    if (step < 0) return count - 1;
    return 0;
}

function stepSelection(index, delta, count) {
    if (count <= 0) return -1;
    var current = Math.max(0, Math.min(count - 1, Number(index) || 0));
    var next = (current + Math.round(Number(delta) || 0)) % count;
    return next < 0 ? next + count : next;
}

.pragma library

var TIME_UNIT_SECONDS = 30;
var MAX_DEPTH = 8;
var FOG_PER_DEPTH = 0.08;

function clampDepth(depth) {
    var value = Number(depth);
    if (isNaN(value)) return MAX_DEPTH;
    return Math.max(0, Math.min(MAX_DEPTH, value));
}

function oldestKnownSeconds(entries) {
    var oldest = 0;
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (!entry.estimated && isFinite(entry.seconds)) oldest = Math.max(oldest, entry.seconds);
    }
    return oldest;
}

function depthForSeconds(seconds, oldestSeconds) {
    var value = Number(seconds);
    if (isNaN(value) || !isFinite(value)) return MAX_DEPTH;
    if (value <= 0 || oldestSeconds <= 0) return 0;
    return clampDepth(MAX_DEPTH * Math.log(1 + value / TIME_UNIT_SECONDS)
        / Math.log(1 + oldestSeconds / TIME_UNIT_SECONDS));
}

function secondsForDepth(depth, oldestSeconds) {
    return TIME_UNIT_SECONDS * (Math.pow(1 + oldestSeconds / TIME_UNIT_SECONDS,
        clampDepth(depth) / MAX_DEPTH) - 1);
}

function tickDepths(oldestSeconds) {
    var depths = [0];
    var limit = Math.log(1 + oldestSeconds / TIME_UNIT_SECONDS) / Math.LN2;
    for (var depth = 1; depth < limit; depth++) depths.push(MAX_DEPTH * depth / limit);
    depths.push(MAX_DEPTH);
    return depths;
}

function fogForDepth(depth) {
    return clampDepth(depth) * FOG_PER_DEPTH;
}

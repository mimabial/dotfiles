.pragma library
.import "Recency.js" as Recency

function dispatchAddress(value) {
    var key = Recency.normalizeAddress(value);
    return key ? "0x" + key : "";
}

function focusRequest(address) {
    var target = dispatchAddress(address);
    return target ? 'hl.dsp.focus({ window = "address:' + target + '" })' : "";
}

function groupIndexFor(address, grouped) {
    var key = Recency.normalizeAddress(address);
    if (!key || !grouped || grouped.length === undefined) return 0;
    for (var i = 0; i < grouped.length; i++) {
        if (Recency.normalizeAddress(grouped[i]) === key) return i + 1;
    }
    return 0;
}

function groupActivateRequest(address, groupIndex) {
    var target = dispatchAddress(address);
    var index = Math.round(Number(groupIndex) || 0);
    if (!target || index <= 0) return "";
    return 'hl.dsp.group.active({ window = "address:' + target + '", index = ' + index + ' })';
}

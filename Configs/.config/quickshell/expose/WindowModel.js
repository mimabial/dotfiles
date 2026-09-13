.pragma library

function ipcFor(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject;
    return ipc && typeof ipc === "object" ? ipc : {};
}

function waylandFor(toplevel) {
    return toplevel && toplevel.wayland ? toplevel.wayland : null;
}

function appIdFor(toplevel) {
    var wayland = waylandFor(toplevel);
    if (wayland && wayland.appId)
        return String(wayland.appId);
    var ipc = ipcFor(toplevel);
    return String(ipc.class || ipc.initialClass || "");
}

function addressFor(toplevel) {
    var address = String((toplevel && toplevel.address) || "");
    return /^[0-9a-fA-F]+$/.test(address) ? "0x" + address : "";
}

function isEligible(toplevel) {
    return Boolean(waylandFor(toplevel)) && ipcFor(toplevel).mapped !== false;
}

function workspaceName(toplevel) {
    var workspace = toplevel && toplevel.workspace ? toplevel.workspace : null;
    return workspace ? String(workspace.name || workspace.id || "—") : "—";
}

function isOnScreen(toplevel, screenName, perMonitor) {
    if (!perMonitor)
        return true;
    var monitor = toplevel && toplevel.monitor ? toplevel.monitor : null;
    return Boolean(monitor) && String(monitor.name || "") === String(screenName || "");
}

function isOnWorkspace(toplevel, workspace) {
    var toplevelWorkspace = toplevel && toplevel.workspace ? toplevel.workspace : null;
    if (!toplevelWorkspace || !workspace)
        return false;
    if (ipcFor(toplevel).pinned === true || toplevelWorkspace === workspace)
        return true;

    var toplevelId = Number(toplevelWorkspace.id);
    var workspaceId = Number(workspace.id);
    if (isFinite(toplevelId) && isFinite(workspaceId) && toplevelId !== 0 && workspaceId !== 0)
        return toplevelId === workspaceId;

    var workspaceName = String(workspace.name || "");
    return Boolean(workspaceName) && String(toplevelWorkspace.name || "") === workspaceName;
}

function aspectRatioFor(toplevel) {
    var size = ipcFor(toplevel).size || [];
    var width = Number(size[0]);
    var height = Number(size[1]);
    if (size.length < 2 || !isFinite(width) || !isFinite(height) || width <= 0 || height <= 0)
        return 1.6;
    return Math.max(0.45, Math.min(4, width / height));
}

function searchTextFor(toplevel) {
    var ipc = ipcFor(toplevel);
    return (appIdFor(toplevel) + " " + String(ipc.class || "") + " "
        + String(ipc.initialClass || "") + " " + String((toplevel && toplevel.title) || "")).toLowerCase();
}

function sameItems(left, right) {
    if (left.length !== right.length)
        return false;
    for (var index = 0; index < left.length; index++)
        if (left[index] !== right[index])
            return false;
    return true;
}

function compositionRows(entries, rowCount) {
    var rows = [];
    for (var row = 0; row < rowCount; row++)
        rows.push({ entries: [], naturalWidth: 0 });
    var ordered = entries.slice().sort(function(a, b) {
        var width = Math.sqrt(b.weight * b.ratio) - Math.sqrt(a.weight * a.ratio);
        return width || a.index - b.index;
    });
    for (var index = 0; index < ordered.length; index++) {
        var target = 0;
        for (var candidate = 1; candidate < rows.length; candidate++)
            if (rows[candidate].naturalWidth < rows[target].naturalWidth
                    || (rows[candidate].naturalWidth === rows[target].naturalWidth
                        && rows[candidate].entries.length < rows[target].entries.length))
                target = candidate;
        var entry = ordered[index];
        rows[target].entries.push(entry);
        rows[target].naturalWidth += Math.sqrt(entry.weight * entry.ratio);
    }
    for (var sortRow = 0; sortRow < rows.length; sortRow++)
        rows[sortRow].entries.sort(function(a, b) { return a.index - b.index; });
    return rows;
}

function composeRows(rows, scale, width, height, gap, padding, footerHeight) {
    var measured = [], totalHeight = 0, footerGap = footerHeight > 0 ? padding : 0;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        var entries = rows[rowIndex].entries, cards = [];
        var totalWidth = Math.max(0, entries.length - 1) * gap, rowHeight = 0;
        for (var index = 0; index < entries.length; index++) {
            var entry = entries[index];
            var card = {
                index: entry.index,
                width: scale * Math.sqrt(entry.weight * entry.ratio) + padding * 2,
                height: scale * Math.sqrt(entry.weight / entry.ratio) + footerHeight + padding * 2 + footerGap
            };
            cards.push(card);
            totalWidth += card.width;
            rowHeight = Math.max(rowHeight, card.height);
        }
        if (totalWidth > width || rowHeight > height)
            return null;
        measured.push({ cards: cards, width: totalWidth, height: rowHeight });
        totalHeight += rowHeight;
    }
    totalHeight += Math.max(0, measured.length - 1) * gap;
    if (totalHeight > height)
        return null;
    var y = (height - totalHeight) / 2, result = [];
    for (var outputRow = 0; outputRow < measured.length; outputRow++) {
        var row = measured[outputRow], x = (width - row.width) / 2;
        for (var cardIndex = 0; cardIndex < row.cards.length; cardIndex++) {
            var card = row.cards[cardIndex];
            result[card.index] = {
                x: x,
                y: y + (row.height - card.height) * (((card.index + outputRow) % 3) / 2),
                width: card.width,
                height: card.height
            };
            x += card.width + (row.cards.length > 1 ? gap : 0);
        }
        y += row.height + (measured.length > 1 ? gap : 0);
    }
    return result;
}

function directionalIndex(selected, dx, dy, layout) {
    if (!layout || !layout[selected])
        return -1;
    var current = layout[selected];
    var currentX = current.x + current.width / 2, currentY = current.y + current.height / 2;
    var best = -1, bestScore = Number.MAX_VALUE;
    for (var index = 0; index < layout.length; index++) {
        if (index === selected || !layout[index])
            continue;
        var candidate = layout[index];
        var deltaX = candidate.x + candidate.width / 2 - currentX;
        var deltaY = candidate.y + candidate.height / 2 - currentY;
        var primary = dx !== 0 ? deltaX * dx : deltaY * dy;
        if (primary <= 0)
            continue;
        var cross = dx !== 0 ? Math.abs(deltaY) : Math.abs(deltaX);
        var score = primary + cross * cross / Math.max(1, primary) * 2;
        if (score < bestScore) {
            bestScore = score;
            best = index;
        }
    }
    return best;
}

function previewRect(toplevel, source, width, height, padding, footerHeight, placement) {
    var ratio = aspectRatioFor(toplevel);
    var maxWidth = width * 0.84, maxHeight = height * 0.78;
    var footerGap = footerHeight > 0 ? padding : 0;
    var previewWidth = Math.max(1, Math.min(maxWidth - padding * 2,
        (maxHeight - footerHeight - padding * 2 - footerGap) * ratio));
    var previewHeight = Math.max(1, previewWidth / ratio);
    var cardWidth = previewWidth + padding * 2;
    var cardHeight = previewHeight + footerHeight + padding * 2 + footerGap;
    var centerX = width / 2, centerY = height / 2;
    if (placement === "in-place" && source) {
        centerX = source.x + source.width / 2;
        centerY = source.y + source.height / 2;
    }
    return {
        x: Math.max(padding, Math.min(width - cardWidth - padding, centerX - cardWidth / 2)),
        y: Math.max(padding, Math.min(height - cardHeight - padding, centerY - cardHeight / 2)),
        width: cardWidth,
        height: cardHeight
    };
}

.pragma library
.import "Depth.js" as Depth

var SIZE_Q = 0.82;          // card scale per step behind the camera
var POS_Q = 0.86;           // how much each step's offset shrinks
var PASSED_FADE = 0.6;      // steps over which a passed card fades out
var PASSED_GROWTH = 0.2;    // extra scale of a card one step past
var VISIBLE_STEPS = 5;      // cards further back fade out; the map shows them

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function stepSum(r) {
    return r <= 0 ? 0 : (1 - Math.pow(POS_Q, r)) / (1 - POS_Q);
}

function fit(boxWidth, boxHeight, aspect) {
    var a = aspect > 0 && isFinite(aspect) ? aspect : 1.6;
    var width = boxWidth;
    var height = width / a;
    if (height > boxHeight) {
        height = boxHeight;
        width = height * a;
    }
    return {
        x: (boxWidth - width) / 2,
        y: (boxHeight - height) / 2,
        width: Math.max(1, width),
        height: Math.max(1, height)
    };
}

function deepStage(width, height, top, bottom, aspect, left) {
    var inset = Math.max(0, Number(left) || 0);
    var a = clamp(Number(aspect) || 1.6, 1.2, 2.4);
    var available = Math.max(1, height - top - bottom);
    var reach = stepSum(VISIBLE_STEPS);
    var room = Math.max(1, width - inset);
    var margin = width * 0.03;
    var availableWidth = Math.max(1, room - margin * 2);
    var rearScale = Math.pow(SIZE_Q, VISIBLE_STEPS);
    var maxScale = 1 + PASSED_GROWTH * Math.min(1, PASSED_FADE);
    var front = fit(availableWidth / (1 + rearScale), available / maxScale, a);
    var spread = Math.min(front.width * 0.85, availableWidth - front.width);
    return {
        frontX: inset + (room - front.width - spread) / 2 + front.width / 2,
        frontY: top + available / 2,
        frontWidth: front.width,
        frontHeight: front.height,
        stepX: reach > 0 ? spread / reach : 0
    };
}

function deepPlane(stage, r) {
    if (r < 0) {
        var passed = Math.min(1.5, -r);
        var grow = 1 + PASSED_GROWTH * Math.min(1, passed);
        return {
            x: stage.frontX - passed * stage.frontWidth * 0.5,
            y: stage.frontY,
            width: stage.frontWidth * grow,
            height: stage.frontHeight * grow,
            scale: grow,
            opacity: clamp(1 - passed / PASSED_FADE, 0, 1),
            z: 1000 + passed
        };
    }
    var scale = Math.pow(SIZE_Q, r);
    var sum = stepSum(r);
    var width = stage.frontWidth * scale;
    var height = stage.frontHeight * scale;
    var right = stage.frontX + stage.frontWidth / 2 + stage.stepX * sum;
    return {
        x: right - width / 2,
        y: stage.frontY,
        width: width,
        height: height,
        scale: scale,
        opacity: clamp(VISIBLE_STEPS + 1 - r, 0, 1),
        z: 1000 - r
    };
}

function soundingY(depth, top, bottom) {
    return top + (bottom - top) * Depth.clampDepth(depth) / Depth.MAX_DEPTH;
}

function soundingMarks(depths, top, bottom, spacing, maxColumns) {
    var list = depths || [];
    var gap = spacing > 0 ? spacing : 6;
    var limit = maxColumns > 0 ? Math.floor(maxColumns) : Infinity;
    var marks = [];
    var rows = [];
    for (var i = 0; i < list.length; i++) {
        var y = soundingY(list[i], top, bottom);
        var row = null;
        for (var j = 0; j < rows.length; j++) {
            if (Math.abs(rows[j].y - y) < gap) {
                row = rows[j];
                break;
            }
        }
        if (!row) {
            row = { y: y, count: 0, last: -1 };
            rows.push(row);
        }
        var column = row.count;
        row.count++;
        var hidden = column >= limit;
        var mark = { y: row.y, column: column, hidden: hidden, more: 0 };
        if (hidden) marks[row.last].more++;
        else row.last = marks.length;
        marks.push(mark);
    }
    return marks;
}

function nearestMark(marks, y, column) {
    var best = -1;
    var bestScore = Infinity;
    for (var i = 0; i < (marks || []).length; i++) {
        if (marks[i].hidden) continue;
        var score = Math.abs(marks[i].y - y) * 4 + Math.abs(marks[i].column - (column || 0));
        if (score < bestScore) {
            bestScore = score;
            best = i;
        }
    }
    return best;
}

function minimapBounds(viewport, windows) {
    var left = viewport.x;
    var top = viewport.y;
    var right = viewport.x + viewport.width;
    var bottom = viewport.y + viewport.height;
    var list = windows || [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (!w || !(w.width > 0) || !(w.height > 0) || !isFinite(w.x) || !isFinite(w.y)) continue;
        left = Math.min(left, w.x);
        top = Math.min(top, w.y);
        right = Math.max(right, w.x + w.width);
        bottom = Math.max(bottom, w.y + w.height);
    }
    return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) };
}

function outside(rect, area) {
    if (!rect || !area) return false;
    return rect.x >= area.x + area.width || rect.x + rect.width <= area.x
        || rect.y >= area.y + area.height || rect.y + rect.height <= area.y;
}

function mapRect(rect, bounds, boxWidth, boxHeight) {
    var scale = Math.min(boxWidth / bounds.width, boxHeight / bounds.height);
    var offsetX = (boxWidth - bounds.width * scale) / 2;
    var offsetY = (boxHeight - bounds.height * scale) / 2;
    return {
        x: offsetX + (rect.x - bounds.x) * scale,
        y: offsetY + (rect.y - bounds.y) * scale,
        width: rect.width * scale,
        height: rect.height * scale
    };
}

function gridRect(position, count, boxWidth, boxHeight, gap) {
    var n = Math.max(1, count);
    var columns = Math.ceil(Math.sqrt(n * boxWidth / Math.max(1, boxHeight)));
    columns = clamp(columns, 1, n);
    var rows = Math.ceil(n / columns);
    var g = gap || 2;
    var width = (boxWidth - g * (columns + 1)) / columns;
    var height = (boxHeight - g * (rows + 1)) / rows;
    var column = position % columns;
    var row = Math.floor(position / columns);
    return { x: g + column * (width + g), y: g + row * (height + g), width: Math.max(1, width), height: Math.max(1, height) };
}

function sameRect(a, b) {
    return Math.abs(a.x - b.x) < 2 && Math.abs(a.y - b.y) < 2
        && Math.abs(a.width - b.width) < 2 && Math.abs(a.height - b.height) < 2;
}

function splitSharedRects(rects, known) {
    var done = [];
    for (var a = 0; a < rects.length; a++) {
        if (done[a]) continue;
        var same = [a];
        for (var b = a + 1; b < rects.length; b++) {
            if (!done[b] && sameRect(known[a], known[b])) same.push(b);
        }
        var base = rects[a];
        var part = base.width / same.length;
        for (var k = 0; k < same.length; k++) {
            rects[same[k]] = { x: base.x + k * part, y: base.y, width: part, height: base.height };
            done[same[k]] = true;
        }
    }
}

function minimapItems(viewport, windows, boxWidth, boxHeight) {
    var list = windows || [];
    var known = [];
    var complete = list.length > 0;
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        var ok = w && w.width > 0 && w.height > 0 && isFinite(w.x) && isFinite(w.y);
        if (!ok) complete = false;
        known.push(ok ? w : null);
    }
    var rects = [];
    if (!complete || !viewport || !(viewport.width > 0)) {
        for (var g = 0; g < list.length; g++) rects.push(gridRect(g, list.length, boxWidth, boxHeight, 3));
        return { rects: rects, viewport: null, bounds: null };
    }
    var bounds = minimapBounds(viewport, known);
    for (var j = 0; j < known.length; j++) rects.push(mapRect(known[j], bounds, boxWidth, boxHeight));

    splitSharedRects(rects, known);
    return { rects: rects, viewport: mapRect(viewport, bounds, boxWidth, boxHeight), bounds: bounds };
}

function mapCards(aspects, available, height, gap, chrome, minWidth) {
    var list = aspects || [];
    var widths = [];
    var total = 0;
    for (var i = 0; i < list.length; i++) {
        var aspect = clamp(Number(list[i]) || 1.6, 0.8, 5);
        var width = height * aspect + chrome;
        widths.push(width);
        total += width;
    }
    total += gap * Math.max(0, list.length - 1);
    var scale = total > available && total > 0 ? (available - gap * Math.max(0, list.length - 1)) / (total - gap * Math.max(0, list.length - 1)) : 1;
    var used = 0;
    for (var j = 0; j < widths.length; j++) {
        widths[j] = Math.max(minWidth || 0, widths[j] * scale);
        used += widths[j];
    }
    var room = available - gap * Math.max(0, list.length - 1);
    if (used > room && used > 0) {
        for (var k = 0; k < widths.length; k++) widths[k] *= Math.max(0, room) / used;
    }
    return { widths: widths, height: height * Math.min(1, Math.max(scale, 0.55)), scale: scale };
}

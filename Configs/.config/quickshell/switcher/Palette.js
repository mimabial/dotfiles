.pragma library

var SOFT_CONTRAST = 5.5;   // secondary text: the caption's details, counts, ages
var FAINT_CONTRAST = 4.5;  // tertiary text: key hints, gauge marks, placeholders
var CARD_CONTRAST = 4.5;   // secondary text on a card
var MARK_CONTRAST = 3;     // lines and marks: the selection ring, the lead

var SOFT_SHARE = 0.34;
var FAINT_SHARE = 0.5;

var DARK_VEIL = [0.75, 0.8, 0.86];
var LIGHT_VEIL = [0.82, 0.86, 0.9];

var WHITE = { r: 1, g: 1, b: 1, a: 1 };
var BLACK = { r: 0, g: 0, b: 0, a: 1 };
var FALLBACK = { foreground: "#cacccc", background: "#101315", accent: "#cacccc", urgent: "#a55555" };

function parse(value) {
    var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    var match = text.match(/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/);
    if (!match) return null;
    var digits = match[1];
    if (digits.length === 3)
        digits = digits[0] + digits[0] + digits[1] + digits[1] + digits[2] + digits[2];
    var alpha = 1;
    if (digits.length === 8) {
        alpha = parseInt(digits.substr(0, 2), 16) / 255;
        digits = digits.substr(2);
    }
    return {
        r: parseInt(digits.substr(0, 2), 16) / 255,
        g: parseInt(digits.substr(2, 2), 16) / 255,
        b: parseInt(digits.substr(4, 2), 16) / 255,
        a: alpha
    };
}

function channel(value) {
    var byte = Math.round(Math.max(0, Math.min(1, value)) * 255);
    return (byte < 16 ? "0" : "") + byte.toString(16);
}

function hex(color, alpha) {
    var a = alpha === undefined ? 1 : alpha;
    var rgb = channel(color.r) + channel(color.g) + channel(color.b);
    return a >= 1 ? "#" + rgb : "#" + channel(a) + rgb;
}

function mix(a, b, share) {
    var t = Math.max(0, Math.min(1, share));
    return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: 1 };
}

function rounded(color) {
    return parse(hex(color));
}

function linear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

function luminance(color) {
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

function contrast(a, b) {
    var la = luminance(a);
    var lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function readable(color, against, ratio, toward) {
    var result = color;
    for (var step = 1; step <= 40 && contrast(result, against) < ratio; step++)
        result = rounded(mix(color, toward, step / 40));
    return result;
}

function tier(foreground, background, share, floors) {
    for (var s = share; s > 0.001; s -= 0.02) {
        var color = rounded(mix(foreground, background, s));
        var holds = true;
        for (var i = 0; i < floors.length && holds; i++)
            holds = contrast(color, floors[i][0]) >= floors[i][1];
        if (holds) return color;
    }
    return foreground;
}

function isLight(foreground, background) {
    return luminance(background) > luminance(foreground);
}

function derive(theme) {
    var source = theme || {};
    var fg = parse(source.foreground) || parse(FALLBACK.foreground);
    var bg = parse(source.background) || parse(FALLBACK.background);
    var accentIn = parse(source.accent) || fg;
    var urgentIn = parse(source.urgent) || parse(FALLBACK.urgent);
    var light = isLight(fg, bg);
    var away = light ? BLACK : WHITE;
    var veil = light ? LIGHT_VEIL : DARK_VEIL;
    var accent = readable(accentIn, bg, MARK_CONTRAST, away);
    var paper = function (share) { return mix(bg, WHITE, share); };
    var cardSelectedTop = light ? paper(0.9) : mix(bg, fg, 0.12);

    return {
        light: light,

        veilTop: hex(bg, veil[0]),
        veilMiddle: hex(bg, veil[1]),
        veilBottom: hex(bg, veil[2]),
        surfaceLight: light ? hex(WHITE, 0.55) : hex(fg, 0.06),
        surfaceLightEnd: light ? hex(WHITE, 0) : hex(fg, 0),
        depthShade: light ? hex(mix(bg, fg, 0.45)) : hex(bg),

        text: hex(fg),
        textSoft: hex(tier(fg, bg, SOFT_SHARE, [[bg, SOFT_CONTRAST], [cardSelectedTop, CARD_CONTRAST]])),
        textFaint: hex(tier(fg, bg, FAINT_SHARE, [[bg, FAINT_CONTRAST]])),
        accent: hex(accent),
        accentText: hex(readable(accentIn, bg, FAINT_CONTRAST, away)),
        urgent: hex(readable(urgentIn, bg, MARK_CONTRAST, away)),
        background: hex(bg),

        cardTop: hex(light ? paper(0.72) : mix(bg, fg, 0.085), source.surfaceOpacity),
        cardBottom: hex(light ? paper(0.5) : mix(bg, fg, 0.035), source.surfaceOpacity),
        cardSelectedTop: hex(cardSelectedTop, source.surfaceOpacity),
        cardSelectedBottom: hex(light ? paper(0.7) : mix(bg, fg, 0.06), source.surfaceOpacity),
        cardBorder: hex(fg, light ? 0.16 : 0.11),
        cardBorderHover: hex(fg, light ? 0.34 : 0.3),
        shadow: light ? hex(mix(fg, BLACK, 0.5), 0.2) : hex(BLACK, 0.55),
        glow: hex(accentIn, light ? 0.34 : 0.38),
        frameEdge: hex(fg, light ? 0.12 : 0.06),
        fog: hex(bg),
        fogStrength: light ? 0.7 : 1,

        panel: light ? hex(paper(0.7), 0.94) : hex(bg, 0.85),
        panelBorder: hex(fg, light ? 0.18 : 0.14),

        mapCard: light ? hex(paper(0.6), 0.8) : hex(fg, 0.045),
        mapCardBorder: hex(fg, light ? 0.13 : 0.1),
        mapCardSelected: light ? hex(mix(paper(0.6), accentIn, 0.08), 0.9) : hex(accentIn, 0.08),
        mapCardSelectedBorder: hex(accent, 0.7),
        screen: light ? hex(fg, 0.05) : hex(BLACK, 0.22),
        tile: light ? hex(paper(0.8)) : hex(mix({ r: 0.12, g: 0.12, b: 0.12, a: 1 }, fg, 0.08), 0.9),
        tileHover: light ? hex(mix(bg, fg, 0.12)) : hex(fg, 0.2),
        tileSelected: light ? hex(mix(paper(0.8), accentIn, 0.24)) : hex(accentIn, 0.36),
        tileBorder: hex(fg, light ? 0.3 : 0.24),
        tileBorderActive: hex(fg, light ? 0.7 : 0.75),

        line: hex(fg, light ? 0.26 : 0.18),
        tick: hex(fg, light ? 0.38 : 0.28),
        mark: hex(fg, light ? 0.55 : 0.6),
        markBorder: hex(fg, 0.5)
    };
}

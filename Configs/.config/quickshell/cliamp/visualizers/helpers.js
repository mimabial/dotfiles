// Shared helpers for all visualizers — ported from  visualizer.go
.pragma library

// scatterHash — deterministic per-dot hash for stable particle patterns
function scatterHash(band, row, col, frame) {
  var f = Math.floor((frame + row * 3 + col) / 3)
  var h = (band * 7919 + row * 6271 + col * 3037 + f * 104729) & 0xFFFFFFFF
  h ^= Math.floor(h / 65536)
  h = (h * 0x45d9f3b) & 0xFFFFFFFF
  h ^= Math.floor(h / 65536)
  return (h % 10000) / 10000.0
}

// shade — same hue and saturation at a different lightness. Palette colours are picked
// to sit as text on a dark background, so they need darkening to work as fills.
function shade(color, light) {
  return hueShift(color, 0, undefined, light)
}

// sampleBandLinear — linear interpolation between band values
function sampleBandLinear(bands, pos) {
  if (bands.length === 0) return 0
  if (bands.length === 1) return bands[0]
  if (pos <= 0) return bands[0]
  var last = bands.length - 1
  if (pos >= last) return bands[last]
  var idx = Math.floor(pos)
  var frac = pos - idx
  return bands[idx] * (1 - frac) + bands[idx + 1] * frac
}

// resampleBandsLinear — resample bands to N columns
function resampleBandsLinear(bands, totalCols) {
  if (totalCols <= 0 || bands.length === 0) return []
  if (bands.length === totalCols) return bands.slice()
  var out = new Array(totalCols)
  if (totalCols === 1) {
    out[0] = sampleBandLinear(bands, (bands.length - 1) / 2)
    return out
  }
  var last = bands.length - 1
  for (var col = 0; col < totalCols; col++) {
    var pos = col / (totalCols - 1) * last
    out[col] = sampleBandLinear(bands, pos)
  }
  return out
}

// bandAvg — mean of bands[lo:hi]
function bandAvg(b, lo, hi) {
  if (lo < 0) lo = 0
  if (hi > b.length) hi = b.length
  if (hi <= lo) return 0
  var s = 0
  for (var i = lo; i < hi; i++) s += b[i]
  return s / (hi - lo)
}

function colorRgb(color, fallback) {
  var value = color || fallback || "#ffffff"
  if (value.r !== undefined && value.g !== undefined && value.b !== undefined) {
    return {
      r: Math.round((value.r <= 1 ? value.r * 255 : value.r)),
      g: Math.round((value.g <= 1 ? value.g * 255 : value.g)),
      b: Math.round((value.b <= 1 ? value.b * 255 : value.b))
    }
  }
  var text = String(value)
  if (/^#[0-9a-f]{3}$/i.test(text)) {
    return { r: parseInt(text[1] + text[1], 16), g: parseInt(text[2] + text[2], 16), b: parseInt(text[3] + text[3], 16) }
  }
  if (/^#[0-9a-f]{6}$/i.test(text)) {
    return { r: parseInt(text.substr(1, 2), 16), g: parseInt(text.substr(3, 2), 16), b: parseInt(text.substr(5, 2), 16) }
  }
  return { r: 255, g: 255, b: 255 }
}

function rgba(color, alpha) {
  var c = colorRgb(color)
  return "rgba(" + c.r + "," + c.g + "," + c.b + "," + alpha + ")"
}

// hsl — {h in degrees, s, l} plus the normalised rgb it came from, so callers that need
// to reason about a colour's own lightness or hue don't re-derive the conversion.
function hsl(color) {
  var c = colorRgb(color)
  var r = c.r / 255, g = c.g / 255, b = c.b / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b), span = max - min
  var l = (max + min) / 2
  var s = span === 0 ? 0 : (l > 0.5 ? span / (2 - max - min) : span / (max + min))
  var h = span === 0 ? 0
    : max === r ? ((g - b) / span) % 6 : max === g ? (b - r) / span + 2 : (r - g) / span + 4
  return { h: (((h * 60) % 360) + 360) % 360, s: s, l: l, r: r, g: g, b: b }
}

// hueShift — rotate a colour around the hue circle. sat and light are optional absolute
// HSL targets; omit them to keep the input's own. Decorative fills should set them,
// because a pale low-chroma accent stays pale through any rotation and five such blobs
// composite to grey mud rather than a nebula.
// Returns a normalised {r,g,b} rather than a string so the result still composes with
// rgba/mixColor/specColor; a fully desaturated input has no hue to rotate and passes
// through unchanged unless sat is given.
function hueShift(color, degrees, sat, light) {
  var c = hsl(color)
  var s = c.s, l = c.l
  if (s === 0 && sat === undefined) return { r: c.r, g: c.g, b: c.b }
  var h = (((c.h + degrees) % 360) + 360) % 360
  if (sat !== undefined) s = sat
  if (light !== undefined) l = light
  var chroma = (1 - Math.abs(2 * l - 1)) * s
  var x = chroma * (1 - Math.abs((h / 60) % 2 - 1))
  var m = l - chroma / 2
  if (h < 60) return { r: chroma + m, g: x + m, b: m }
  if (h < 120) return { r: x + m, g: chroma + m, b: m }
  if (h < 180) return { r: m, g: chroma + m, b: x + m }
  if (h < 240) return { r: m, g: x + m, b: chroma + m }
  if (h < 300) return { r: x + m, g: m, b: chroma + m }
  return { r: chroma + m, g: m, b: x + m }
}

function mixColor(first, second, amount, alpha) {
  var a = colorRgb(first), b = colorRgb(second)
  var t = Math.max(0, Math.min(1, amount))
  return "rgba(" + Math.round(a.r + (b.r - a.r) * t) + ","
    + Math.round(a.g + (b.g - a.g) * t) + ","
    + Math.round(a.b + (b.b - a.b) * t) + "," + alpha + ")"
}

// A continuous spectrum made only from the theme's dim, accent and foreground roles.
function specColor(d, norm, alpha) {
  var level = Math.max(0, Math.min(1, norm))
  if (level < 0.5) return mixColor(d.dim, d.accent, level * 2, alpha === undefined ? 0.9 : alpha)
  return mixColor(d.accent, d.foreground, (level - 0.5) * 2, alpha === undefined ? 0.9 : alpha)
}

// specTiers — the three spectrum tiers as cliamp paints them: ANSI bright green,
// yellow and red (styles.go SpectrumLow/Mid/High), indexed by the tier tag a
// visualizer assigns. Falls back to the accent when a slot is absent.
function specTiers(d) {
  var c = d.colors || []
  return [rgba(c[10] || d.accent, 1), rgba(c[11] || d.accent, 1), rgba(c[9] || d.foreground, 1)]
}

function playerTiers(d) {
  return [rgba(d.accent, 1), rgba(d.foreground, 1), rgba(d.success || d.foreground, 1)]
}

// specTag — cliamp's row colour tier (visualizer.go specTag): a hard three-way split
// on normalised height, not a gradient. specWrap tags every rendered row with it.
function specTag(norm) {
  return norm >= 0.6 ? 2 : norm >= 0.3 ? 1 : 0
}

// tierRamp — one tier colour per pixel row, built once per frame.
function tierRamp(tiers, height) {
  var steps = Math.max(1, Math.ceil(height)) + 1
  var out = new Array(steps)
  for (var i = 0; i < steps; i++) out[i] = tiers[specTag(i / height)]
  return out
}

function specTierRamp(d, height) {
  return tierRamp(specTiers(d), height)
}

function playerTierRamp(d, height) {
  return tierRamp(playerTiers(d), height)
}

// specRamp — one specColor per pixel row, built once per frame. Every per-pixel
// visualizer asks for a colour that varies only with the row, and each specColor parses
// two hex strings and builds an rgba() string, so calling it per pixel costs ~50x what
// the ramp does. One spare slot absorbs a rounded bar height landing on h.
function specRamp(d, height, alpha) {
  var steps = Math.max(1, Math.ceil(height)) + 1
  var out = new Array(steps)
  for (var i = 0; i < steps; i++) out[i] = specColor(d, i / height, alpha)
  return out
}

// LCG RNG — uses 64-bit constants that JS doubles can't handle precisely.
// 32-bit Numerical Recipes LCG produces equivalent deterministic pseudo-randomness.
function lcgRng(state) {
  state.v = (state.v * 1664525 + 1013904223) & 0xFFFFFFFF
  return state.v
}

// Extract [0,1) float from upper bits of an LCG state. The shift must be unsigned:
// lcgRng masks with & 0xFFFFFFFF, which yields a signed 32-bit int, so an arithmetic
// >> returns a negative float half the time and every `rand01() < p` test passes.
function lcgRand01(state) {
  lcgRng(state)
  return ((state.v >>> 16) % 1000) / 1000.0
}

// Universal rounded rectangle path compatible with all Qt Quick Canvas versions
function roundedRect(ctx, x, y, w, h, r) {
  if (w <= 0 || h <= 0) return
  if (r <= 0) {
    ctx.rect(x, y, w, h)
    return
  }
  var radius = Math.min(r, w / 2.0, h / 2.0)
  ctx.moveTo(x + radius, y)
  ctx.lineTo(x + w - radius, y)
  ctx.arcTo(x + w, y, x + w, y + radius, radius)
  ctx.lineTo(x + w, y + h - radius)
  ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius)
  ctx.lineTo(x + radius, y + h)
  ctx.arcTo(x, y + h, x, y + h - radius, radius)
  ctx.lineTo(x, y + radius)
  ctx.arcTo(x, y, x + radius, y, radius)
}

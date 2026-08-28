// Shared helpers for all visualizers — ported from  visualizer.go
.pragma library

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

// LCG RNG — uses 64-bit constants that JS doubles can't handle precisely.
// 32-bit Numerical Recipes LCG produces equivalent deterministic pseudo-randomness.
function lcgRng(state) {
  state.v = (state.v * 1664525 + 1013904223) & 0xFFFFFFFF
  return state.v
}

// Extract [0,1) float from upper bits of an LCG state (use >>16, not >>33)
function lcgRand01(state) {
  lcgRng(state)
  return ((state.v >> 16) % 1000) / 1000.0
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

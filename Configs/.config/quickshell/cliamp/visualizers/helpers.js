.pragma library

function scatterHash(band, row, col, frame) {
  var f = Math.floor((frame + row * 3 + col) / 3)
  var h = (band * 7919 + row * 6271 + col * 3037 + f * 104729) & 0xFFFFFFFF
  h ^= Math.floor(h / 65536)
  h = (h * 0x45d9f3b) & 0xFFFFFFFF
  h ^= Math.floor(h / 65536)
  return (h % 10000) / 10000.0
}

function shade(color, light) {
  return hueShift(color, 0, undefined, light)
}

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

function bandAvg(bands, firstBand, endBand) {
  if (firstBand < 0) firstBand = 0
  if (endBand > bands.length) endBand = bands.length
  if (endBand <= firstBand) return 0
  var sum = 0
  for (var i = firstBand; i < endBand; i++) sum += bands[i]
  return sum / (endBand - firstBand)
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

function hueShift(color, degrees, saturation, lightness) {
  var c = hsl(color)
  var s = c.s, l = c.l
  if (s === 0 && saturation === undefined) return { r: c.r, g: c.g, b: c.b }
  var h = (((c.h + degrees) % 360) + 360) % 360
  if (saturation !== undefined) s = saturation
  if (lightness !== undefined) l = lightness
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

function specColor(d, norm, alpha) {
  var level = Math.max(0, Math.min(1, norm))
  if (level < 0.5) return mixColor(d.dim, d.accent, level * 2, alpha === undefined ? 0.9 : alpha)
  return mixColor(d.accent, d.foreground, (level - 0.5) * 2, alpha === undefined ? 0.9 : alpha)
}

function specTiers(d) {
  var c = d.colors || []
  return [rgba(c[10] || d.accent, 1), rgba(c[11] || d.accent, 1), rgba(c[9] || d.foreground, 1)]
}

function playerSpectrum(d) {
  return [d.accent, d.foreground, d.success || d.foreground]
}

function playerTiers(d) {
  return playerSpectrum(d).map(function (color) { return rgba(color, 1) })
}

function specTag(norm) {
  return norm >= 0.6 ? 2 : norm >= 0.3 ? 1 : 0
}

function tierRamp(tiers, height) {
  var steps = Math.max(1, Math.ceil(height)) + 1
  var out = new Array(steps)
  for (var i = 0; i < steps; i++) out[i] = tiers[specTag(i / height)]
  return out
}

function playerTierRamp(d, height) {
  return tierRamp(playerTiers(d), height)
}

function specRamp(d, height, alpha) {
  var steps = Math.max(1, Math.ceil(height)) + 1
  var out = new Array(steps)
  for (var i = 0; i < steps; i++) out[i] = specColor(d, i / height, alpha)
  return out
}

function lcgRng(state) {
  state.v = (state.v * 1664525 + 1013904223) & 0xFFFFFFFF
  return state.v
}

function lcgRand01(state) {
  lcgRng(state)
  return ((state.v >>> 16) % 1000) / 1000.0
}

function roundedRect(canvas, x, y, width, height, r) {
  if (width <= 0 || height <= 0) return
  if (r <= 0) {
    canvas.rect(x, y, width, height)
    return
  }
  var radius = Math.min(r, width / 2.0, height / 2.0)
  canvas.moveTo(x + radius, y)
  canvas.lineTo(x + width - radius, y)
  canvas.arcTo(x + width, y, x + width, y + radius, radius)
  canvas.lineTo(x + width, y + height - radius)
  canvas.arcTo(x + width, y + height, x + width - radius, y + height, radius)
  canvas.lineTo(x + radius, y + height)
  canvas.arcTo(x, y + height, x, y + height - radius, radius)
  canvas.lineTo(x, y + radius)
  canvas.arcTo(x, y, x + radius, y, radius)
}

var CLIAMP_TICK_MS = 50
var CLIAMP_MAX_CATCH_UP_TICKS = 4
var CLIAMP_BAND_EDGES_HZ = [20, 100, 200, 400, 800, 1600, 3200, 6400, 12800, 16000, 20000]

function cliampTicks(clock) {
  var now = Date.now()
  if (!clock.last) {
    clock.last = now
    clock.pending = 0
    return 1
  }
  clock.pending += now - clock.last
  clock.last = now
  var ticks = Math.floor(clock.pending / CLIAMP_TICK_MS)
  if (ticks > CLIAMP_MAX_CATCH_UP_TICKS) {
    clock.pending = 0
    return CLIAMP_MAX_CATCH_UP_TICKS
  }
  clock.pending -= ticks * CLIAMP_TICK_MS
  return ticks
}

function cliampTickFraction(clock) {
  return Math.min(1, clock.pending / CLIAMP_TICK_MS)
}

function cliampBands(bands, edgesHz) {
  var out = new Array(CLIAMP_BAND_EDGES_HZ.length - 1).fill(0)
  if (edgesHz.length !== bands.length + 1) return out
  for (var band = 0; band < out.length; band++) {
    var lo = Math.log(CLIAMP_BAND_EDGES_HZ[band]), hi = Math.log(CLIAMP_BAND_EDGES_HZ[band + 1])
    var sum = 0, weight = 0
    for (var i = 0; i < bands.length; i++) {
      var overlap = Math.min(hi, Math.log(edgesHz[i + 1])) - Math.max(lo, Math.log(edgesHz[i]))
      if (overlap > 0) {
        sum += bands[i] * overlap
        weight += overlap
      }
    }
    out[band] = weight > 0 ? sum / weight : 0
  }
  return out
}

function paintTagGrid(canvas, tags, cols, rows, colors) {
  var runs = colors.map(function () { return [] })
  for (var y = 0; y < rows; y++) {
    var row = y * cols
    for (var x = 0; x < cols;) {
      var tag = tags[row + x], start = x
      while (++x < cols && tags[row + x] === tag) {}
      if (tag) runs[tag].push(start, y, x - start)
    }
  }
  for (var t = 1; t < colors.length; t++) {
    canvas.fillStyle = colors[t]
    for (var i = 0; i < runs[t].length; i += 3) canvas.fillRect(runs[t][i], runs[t][i + 1], runs[t][i + 2], 1)
  }
}

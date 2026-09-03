// Heatmap Wave — Dynamic Thermal Intensity Energy-Color Mapped Visualizer with full color fill
.pragma library
.import "helpers.js" as H

// Thermal ramp walked across the theme's own palette rather than synthesised from the
// accent: blue -> teal -> green -> yellow -> pink is a real temperature sweep, and every
// stop is a colour the theme already uses. Falls back to specColor if c0-c15 are absent.
var HEAT = [4, 6, 2, 3, 1]

function heatColor(d, val, alpha) {
  var pal = d.colors || []
  if (pal.length < 16) return H.specColor(d, val, alpha)
  var v = Math.max(0.0, Math.min(1.0, val)) * (HEAT.length - 1)
  var i = Math.min(HEAT.length - 2, Math.floor(v))
  return H.mixColor(pal[HEAT[i]], pal[HEAT[i + 1]], v - i, alpha)
}

function render(ctx, d) {
  var bands = d.bands || []
  var w = d.width, h = d.height, frame = d.frame || 0
  var isPlaying = d.playing
  var beatDrop = d.beatDrop || 0
  var midY = h / 2.0

  // 60 thermal intensity bars
  var numBars = 60
  var resampled = H.resampleBandsLinear(bands, numBars)

  var margin = 6
  var totalDrawW = w - margin * 2
  var gap = 1.8
  var barW = Math.max(2.0, (totalDrawW - (numBars - 1) * gap) / numBars)
  var actualW = numBars * barW + (numBars - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  for (var i = 0; i < numBars; i++) {
    var bx = startX + i * (barW + gap)

    // Track dynamic profile envelope
    var env = Math.sin((i / numBars) * Math.PI)
    var shapeVal = 0.16 + env * 0.48 + Math.sin(i * 0.75 + 0.3) * 0.14
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 2 && i <= 14) ? (beatDrop * 0.26) : 0.0

    // Thermal energy intensity (0.0 to 1.0)
    var intensity = Math.min(1.0, shapeVal * 0.38 + energy * 0.62 + kick)
    var barH = Math.max(barW, intensity * (h * 0.86))
    var by = midY - (barH / 2.0)
    var r = Math.min(barW / 2.0, 1.5)

    // Full thermal radiant gradient from top to bottom across all bars
    var grad = ctx.createLinearGradient(0, by, 0, by + barH)
    grad.addColorStop(0, heatColor(d, intensity + 0.25, 0.98))
    grad.addColorStop(0.5, heatColor(d, intensity, 0.92))
    grad.addColorStop(1, heatColor(d, intensity - 0.20, 0.85))
    ctx.fillStyle = grad

    ctx.beginPath()
    H.roundedRect(ctx, bx, by, barW, barH, r)
    ctx.fill()
  }
}

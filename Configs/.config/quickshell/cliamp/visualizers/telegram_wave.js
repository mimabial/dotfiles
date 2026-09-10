// Telegram Wave — Full-width rounded capsule voice message waveform with full color fill
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands || []
  var w = d.width, h = d.height, frame = d.frame || 0
  var isPlaying = d.playing
  var beatDrop = d.beatDrop || 0
  var midY = h / 2.0

  var numPills = 56
  var resampled = H.resampleBandsLinear(bands, numPills)

  var margin = 6
  var totalDrawW = w - margin * 2
  var gap = 2.4
  var pillW = Math.max(2.4, (totalDrawW - (numPills - 1) * gap) / numPills)
  var actualW = numPills * pillW + (numPills - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  for (var i = 0; i < numPills; i++) {
    var px = startX + i * (pillW + gap)

    var env = Math.sin((i / numPills) * Math.PI)
    var shapeVal = 0.18 + env * 0.48 + Math.sin(i * 0.85 + 0.3) * 0.14
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 2 && i <= 12) ? (beatDrop * 0.22) : 0.0

    var pillH = Math.max(pillW, ((shapeVal * 0.38) + (energy * 0.64) + kick) * (h * 0.86))
    var py = midY - (pillH / 2.0)
    var r = pillW / 2.0

    var grad = ctx.createLinearGradient(0, py, 0, py + pillH)
    grad.addColorStop(0, H.rgba(d.foreground, 0.98))
    grad.addColorStop(0.25, H.mixColor(d.accent, d.foreground, 0.35, 0.95))
    grad.addColorStop(1, H.rgba(d.accent, 0.88))
    ctx.fillStyle = grad

    ctx.beginPath()
    H.roundedRect(ctx, px, py, pillW, pillH, r)
    ctx.fill()
  }
}

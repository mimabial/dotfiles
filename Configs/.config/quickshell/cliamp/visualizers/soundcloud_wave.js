// SoundCloud Wave — Ultra-thin high-density asymmetrical waveform with full vibrant color fill
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands || []
  var w = d.width, h = d.height, frame = d.frame || 0
  var isPlaying = d.playing
  var beatDrop = d.beatDrop || 0

  var numBars = 84
  var resampled = H.resampleBandsLinear(bands, numBars)

  var margin = 6
  var totalDrawW = w - margin * 2
  var gap = 1.4
  var barW = Math.max(1.2, (totalDrawW - (numBars - 1) * gap) / numBars)
  var actualW = numBars * barW + (numBars - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  var baselineY = h * 0.66
  var maxTopH = baselineY - 4
  var maxBotH = (h - baselineY) - 4

  for (var i = 0; i < numBars; i++) {
    var bx = startX + i * (barW + gap)

    var env = Math.sin((i / numBars) * Math.PI)
    var shapeVal = 0.16 + env * 0.48 + Math.sin(i * 0.55 + 0.2) * 0.12 + Math.sin(i * 1.3) * 0.08
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 3 && i <= 20) ? (beatDrop * 0.22) : 0.0

    var topNorm = Math.min(1.0, shapeVal * 0.38 + energy * 0.65 + kick)
    var topH = Math.max(3.0, topNorm * maxTopH)

    var botH = Math.max(1.5, topH * 0.28)

    var topY = baselineY - topH
    var botY = baselineY + 1.2 // 1.2px horizon slit
    var r = Math.min(barW / 2.0, 0.8)

    var topGrad = ctx.createLinearGradient(0, topY, 0, baselineY)
    topGrad.addColorStop(0, H.rgba(d.foreground, 0.98))
    topGrad.addColorStop(0.20, H.mixColor(d.accent, d.foreground, 0.35, 0.95))
    topGrad.addColorStop(1, H.rgba(d.accent, 0.88))
    ctx.fillStyle = topGrad
    ctx.beginPath()
    H.roundedRect(ctx, bx, topY, barW, topH, r)
    ctx.fill()

    var botGrad = ctx.createLinearGradient(0, botY, 0, botY + botH)
    botGrad.addColorStop(0, H.rgba(d.accent, 0.55))
    botGrad.addColorStop(1, H.rgba(d.accent, 0.15))
    ctx.fillStyle = botGrad
    ctx.beginPath()
    H.roundedRect(ctx, bx, botY, barW, botH, r)
    ctx.fill()
  }
}

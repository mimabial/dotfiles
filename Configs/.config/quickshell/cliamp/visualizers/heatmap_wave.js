.pragma library
.import "helpers.js" as VisualizerHelpers

var HEAT = [4, 6, 2, 3, 1]

function heatColor(d, val, alpha) {
  var palette = d.colors || []
  if (palette.length < 16) return VisualizerHelpers.specColor(d, val, alpha)
  var v = Math.max(0.0, Math.min(1.0, val)) * (HEAT.length - 1)
  var i = Math.min(HEAT.length - 2, Math.floor(v))
  return VisualizerHelpers.mixColor(palette[HEAT[i]], palette[HEAT[i + 1]], v - i, alpha)
}

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var beatDrop = frameData.beatDrop || 0
  var midY = height / 2.0

  var numBars = 60
  var resampled = VisualizerHelpers.resampleBandsLinear(bands, numBars)

  var margin = 6
  var totalDrawW = width - margin * 2
  var gap = 1.8
  var barW = Math.max(2.0, (totalDrawW - (numBars - 1) * gap) / numBars)
  var actualW = numBars * barW + (numBars - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  for (var i = 0; i < numBars; i++) {
    var centerX = startX + i * (barW + gap)

    var env = Math.sin((i / numBars) * Math.PI)
    var shapeVal = 0.16 + env * 0.48 + Math.sin(i * 0.75 + 0.3) * 0.14
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 2 && i <= 14) ? (beatDrop * 0.26) : 0.0

    var intensity = Math.min(1.0, shapeVal * 0.38 + energy * 0.62 + kick)
    var barH = Math.max(barW, intensity * (height * 0.86))
    var centerY = midY - (barH / 2.0)
    var r = Math.min(barW / 2.0, 1.5)

    var gradient = canvas.createLinearGradient(0, centerY, 0, centerY + barH)
    gradient.addColorStop(0, heatColor(frameData, intensity + 0.25, 0.98))
    gradient.addColorStop(0.5, heatColor(frameData, intensity, 0.92))
    gradient.addColorStop(1, heatColor(frameData, intensity - 0.20, 0.85))
    canvas.fillStyle = gradient

    canvas.beginPath()
    VisualizerHelpers.roundedRect(canvas, centerX, centerY, barW, barH, r)
    canvas.fill()
  }
}

.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var beatDrop = frameData.beatDrop || 0

  var numBars = 64
  var resampled = VisualizerHelpers.resampleBandsLinear(bands, numBars)

  var margin = 6
  var totalDrawW = width - margin * 2
  var gap = 1.8
  var barW = Math.max(2.0, (totalDrawW - (numBars - 1) * gap) / numBars)
  var actualW = numBars * barW + (numBars - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  var baselineY = height - 6
  var maxH = baselineY - 4

  var capColor = VisualizerHelpers.rgba(frameData.foreground, 0.98)
  var midColor = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, 0.35, 0.95)
  var footColor = VisualizerHelpers.rgba(frameData.accent, 0.85)

  for (var i = 0; i < numBars; i++) {
    var centerX = startX + i * (barW + gap)

    var env = Math.sin((i / numBars) * Math.PI)
    var shapeVal = 0.15 + env * 0.48 + Math.sin(i * 0.7 + 0.4) * 0.12
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 2 && i <= 14) ? (beatDrop * 0.22) : 0.0

    var barH = Math.max(3.0, (shapeVal * 0.38 + energy * 0.62 + kick) * maxH)
    var centerY = baselineY - barH
    var r = Math.min(barW / 2.0, 1.2)

    var gradient = canvas.createLinearGradient(0, centerY, 0, baselineY)
    gradient.addColorStop(0, capColor)
    gradient.addColorStop(0.25, midColor)
    gradient.addColorStop(1, footColor)
    canvas.fillStyle = gradient

    canvas.beginPath()
    VisualizerHelpers.roundedRect(canvas, centerX, centerY, barW, barH, r)
    canvas.fill()
  }

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.18)
  canvas.fillRect(startX, baselineY + 1, actualW, 1)
}

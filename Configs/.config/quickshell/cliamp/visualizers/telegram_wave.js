.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var beatDrop = frameData.beatDrop || 0
  var midY = height / 2.0

  var numPills = 56
  var resampled = VisualizerHelpers.resampleBandsLinear(bands, numPills)

  var margin = 6
  var totalDrawW = width - margin * 2
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

    var pillH = Math.max(pillW, ((shapeVal * 0.38) + (energy * 0.64) + kick) * (height * 0.86))
    var py = midY - (pillH / 2.0)
    var r = pillW / 2.0

    var gradient = canvas.createLinearGradient(0, py, 0, py + pillH)
    gradient.addColorStop(0, VisualizerHelpers.rgba(frameData.foreground, 0.98))
    gradient.addColorStop(0.25, VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, 0.35, 0.95))
    gradient.addColorStop(1, VisualizerHelpers.rgba(frameData.accent, 0.88))
    canvas.fillStyle = gradient

    canvas.beginPath()
    VisualizerHelpers.roundedRect(canvas, px, py, pillW, pillH, r)
    canvas.fill()
  }
}

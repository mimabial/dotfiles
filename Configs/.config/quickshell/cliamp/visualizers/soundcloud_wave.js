.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var beatDrop = frameData.beatDrop || 0

  var numBars = 84
  var resampled = VisualizerHelpers.resampleBandsLinear(bands, numBars)

  var margin = 6
  var totalDrawW = width - margin * 2
  var gap = 1.4
  var barW = Math.max(1.2, (totalDrawW - (numBars - 1) * gap) / numBars)
  var actualW = numBars * barW + (numBars - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  var baselineY = height * 0.66
  var maxTopH = baselineY - 4
  var maxBotH = (height - baselineY) - 4

  for (var i = 0; i < numBars; i++) {
    var centerX = startX + i * (barW + gap)

    var env = Math.sin((i / numBars) * Math.PI)
    var shapeVal = 0.16 + env * 0.48 + Math.sin(i * 0.55 + 0.2) * 0.12 + Math.sin(i * 1.3) * 0.08
    var energy = isPlaying ? (resampled[i] || 0) : 0.0
    var kick = (i >= 3 && i <= 20) ? (beatDrop * 0.22) : 0.0

    var topNorm = Math.min(1.0, shapeVal * 0.38 + energy * 0.65 + kick)
    var topH = Math.max(3.0, topNorm * maxTopH)

    var botH = Math.max(1.5, topH * 0.28)

    var topY = baselineY - topH
    var horizonSlit = 1.2
    var botY = baselineY + horizonSlit
    var r = Math.min(barW / 2.0, 0.8)

    var topGrad = canvas.createLinearGradient(0, topY, 0, baselineY)
    topGrad.addColorStop(0, VisualizerHelpers.rgba(frameData.foreground, 0.98))
    topGrad.addColorStop(0.20, VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, 0.35, 0.95))
    topGrad.addColorStop(1, VisualizerHelpers.rgba(frameData.accent, 0.88))
    canvas.fillStyle = topGrad
    canvas.beginPath()
    VisualizerHelpers.roundedRect(canvas, centerX, topY, barW, topH, r)
    canvas.fill()

    var botGrad = canvas.createLinearGradient(0, botY, 0, botY + botH)
    botGrad.addColorStop(0, VisualizerHelpers.rgba(frameData.accent, 0.55))
    botGrad.addColorStop(1, VisualizerHelpers.rgba(frameData.accent, 0.15))
    canvas.fillStyle = botGrad
    canvas.beginPath()
    VisualizerHelpers.roundedRect(canvas, centerX, botY, barW, botH, r)
    canvas.fill()
  }
}

.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var beatDrop = frameData.beatDrop || 0
  var midY = height / 2.0

  var numCols = 44
  var resampled = VisualizerHelpers.resampleBandsLinear(bands, numCols)

  var margin = 6
  var totalDrawW = width - margin * 2
  var gap = 2.5
  var colW = Math.max(2.5, (totalDrawW - (numCols - 1) * gap) / numCols)
  var actualW = numCols * colW + (numCols - 1) * gap
  var startX = margin + (totalDrawW - actualW) / 2.0

  var numSegs = 11
  var segH = 2.4
  var segGap = 1.4
  var totalMatrixH = numSegs * segH + (numSegs - 1) * segGap
  var matrixStartY = midY - (totalMatrixH / 2.0)

  var centerIdx = Math.floor(numSegs / 2)
  var segColors = []
  for (var si = 0; si < numSegs; si++) {
    var tone = Math.abs(si - centerIdx) / centerIdx
    segColors.push(VisualizerHelpers.specColor(frameData, tone, si === centerIdx ? 1.0 : 0.95))
  }
  var unlitColor = VisualizerHelpers.rgba(frameData.foreground, 0.06)

  for (var col = 0; col < numCols; col++) {
    var cx = startX + col * (colW + gap)

    var env = Math.sin((col / numCols) * Math.PI)
    var shapeVal = 0.20 + env * 0.45 + Math.sin(col * 0.8) * 0.15
    var energy = isPlaying ? (resampled[col] || 0) : 0.0
    var kick = (col >= 2 && col <= 12) ? (beatDrop * 0.25) : 0.0

    var norm = Math.min(1.0, shapeVal * 0.40 + energy * 0.65 + kick)
    var activeRadius = Math.max(1, Math.round(norm * 5))

    for (var s = 0; s < numSegs; s++) {
      var sy = matrixStartY + s * (segH + segGap)
      var distFromCenter = Math.abs(s - centerIdx)
      var isLit = distFromCenter <= activeRadius

      canvas.fillStyle = isLit ? segColors[s] : unlitColor

      canvas.beginPath()
      VisualizerHelpers.roundedRect(canvas, cx, sy, colW, segH, 0.8)
      canvas.fill()
    }
  }
}

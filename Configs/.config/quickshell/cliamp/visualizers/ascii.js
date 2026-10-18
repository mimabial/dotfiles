.pragma library
.import "helpers.js" as VisualizerHelpers

var BAR_W = 1
var BAR_GAP = 1

function shadeBlock(level, rowBottom, rowTop) {
  if (level >= rowTop) return "█"
  if (level > rowBottom) {
    var frac = (level - rowBottom) / (rowTop - rowBottom)
    if (frac >= 0.75) return "▓"
    if (frac >= 0.50) return "▒"
    if (frac >= 0.25) return "░"
  }
  return ""
}

function render(canvas, frameData) {
  var width = frameData.width, height = frameData.height

  var charW = 6
  var charH = 10
  var numCols = Math.floor(width / charW)
  var numRows = Math.floor(height / charH)
  if (numCols < 1 || numRows < 1) return

  var activeCols = Math.max(1, Math.floor((numCols + BAR_GAP) / (BAR_W + BAR_GAP)))
  var cols = VisualizerHelpers.resampleBandsLinear(frameData.bands, activeCols)
  var tiers = VisualizerHelpers.playerTiers(frameData)
  var stepPx = charW * (BAR_W + BAR_GAP)

  canvas.save()
  canvas.font = "bold 10px monospace"
  canvas.textAlign = "center"
  canvas.textBaseline = "middle"

  for (var row = 0; row < numRows; row++) {
    var rowBottom = (numRows - 1 - row) / numRows
    var rowTop = (numRows - row) / numRows
    var cy = row * charH + charH / 2
    canvas.fillStyle = tiers[VisualizerHelpers.specTag(rowBottom)]

    for (var c = 0; c < activeCols; c++) {
      var glyph = shadeBlock(cols[c] || 0, rowBottom, rowTop)
      if (glyph === "") continue
      canvas.fillText(glyph, c * stepPx + charW / 2, cy)
    }
  }

  canvas.restore()
}

// Ascii — exact cliamp vis_ascii.go: shade-block columns (█ ▓ ▒ ░) on the same
// 1-wide/1-gap layout as ClassicPeak
.pragma library
.import "helpers.js" as H

var BAR_W = 1
var BAR_GAP = 1

// shadeBlock: fractional fill within a row, quartered.
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

function render(ctx, d) {
  var w = d.width, h = d.height

  var charW = 6
  var charH = 10
  var numCols = Math.floor(w / charW)
  var numRows = Math.floor(h / charH)
  if (numCols < 1 || numRows < 1) return

  var activeCols = Math.max(1, Math.floor((numCols + BAR_GAP) / (BAR_W + BAR_GAP)))
  var cols = H.resampleBandsLinear(d.bands, activeCols)
  var tiers = H.playerTiers(d)
  var stepPx = charW * (BAR_W + BAR_GAP)

  ctx.save()
  ctx.font = "bold 10px monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"

  for (var row = 0; row < numRows; row++) {
    var rowBottom = (numRows - 1 - row) / numRows
    var rowTop = (numRows - row) / numRows
    var cy = row * charH + charH / 2
    ctx.fillStyle = tiers[H.specTag(rowBottom)]

    for (var c = 0; c < activeCols; c++) {
      var glyph = shadeBlock(cols[c] || 0, rowBottom, rowTop)
      if (glyph === "") continue
      ctx.fillText(glyph, c * stepPx + charW / 2, cy)
    }
  }

  ctx.restore()
}

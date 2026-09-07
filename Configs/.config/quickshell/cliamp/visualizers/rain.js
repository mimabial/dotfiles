// Rain — exact cliamp vis_rain.go: bar-height columns filled with falling streaks
.pragma library
.import "helpers.js" as H

// visBandWidth from visualizer.go: bands share the row, one gap column between each.
function bandWidths(bandCount, panelWidth) {
  var out = new Array(bandCount)
  var visible = Math.min(bandCount, panelWidth)
  var gaps = Math.min(visible - 1, Math.max(0, panelWidth - visible))
  var bandCols = panelWidth - gaps
  var base = Math.floor(bandCols / visible)
  var extra = bandCols % visible
  for (var b = 0; b < bandCount; b++) out[b] = b >= visible ? 0 : (b < extra ? base + 1 : base)
  return out
}

function render(ctx, d) {
  var bands = d.bands, w = d.width, h = d.height
  var frame = d.frame, playing = d.playing

  var charW = 8
  var charH = 10
  var numCols = Math.floor(w / charW)
  var numRows = Math.floor(h / charH)
  var bandCount = bands.length
  if (numCols < 1 || numRows < 1 || bandCount < 1) return

  var widths = bandWidths(bandCount, numCols)
  var tiers = H.specTiers(d)
  var gate = Math.floor(frame / 12)

  ctx.save()
  ctx.font = "bold 9px monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"

  for (var row = 0; row < numRows; row++) {
    var rowNorm = (numRows - 1 - row) / numRows
    var cy = row * charH + charH / 2
    var col = 0

    for (var b = 0; b < bandCount; b++) {
      var level = playing ? Math.min(1.0, Math.max(0.0, bands[b] || 0)) : 0.0

      for (var k = 0; k < widths[b]; k++, col++) {
        if (rowNorm >= level) continue
        if (H.scatterHash(b, 0, col, gate) > level * 1.6 + 0.1) continue

        var seed = col * 7919 + 104729
        var speed = 1 + (seed % 3)
        var dropLen = 2 + (Math.floor(seed / 7) % 3)
        var cycleLen = numRows + dropLen + 3
        var offset = Math.floor(seed / 13) % cycleLen
        var dist = ((Math.floor(frame / speed) + offset) % cycleLen) - row
        if (dist < 0 || dist >= dropLen) continue

        ctx.fillStyle = tiers[dist === 0 ? 2 : dist === 1 ? 1 : 0]
        ctx.fillText(dist === 0 ? "┃" : dist === 1 ? "│" : ":", col * charW + charW / 2, cy)
      }
      if (b < bandCount - 1) col++
    }
  }

  ctx.restore()
}

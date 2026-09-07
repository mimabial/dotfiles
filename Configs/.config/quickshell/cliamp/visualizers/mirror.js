// Mirror — exact cliamp vis_mirror.go: one bar per slot mirrored about a persistent
// axis, rasterised through the 4x2 braille dot grid the terminal uses
.pragma library
.import "helpers.js" as H

var SPAN_PERCENT = 84

// brailleBit from visualizer.go: (dot row, dot col) to its bit in U+2800.
var BRAILLE_BIT = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]

function render(ctx, d) {
  var bands = d.bands, w = d.width, h = d.height

  var charW = 6
  var charH = 10
  var numCols = Math.floor(w / charW)
  var numRows = Math.floor(h / charH)
  if (numCols < 1 || numRows < 1) return

  var dotRows = numRows * 4
  var dotCols = numCols * 2
  var span = Math.max(2, Math.floor(dotCols * SPAN_PERCENT / 100))
  span = Math.min(dotCols, span - span % 2)
  var barCount = Math.max(1, Math.floor(span / 2))
  var x0 = Math.floor((dotCols - span) / 2)
  var axisY = Math.floor(dotRows / 2)
  var maxRadius = Math.min(axisY, dotRows - 1 - axisY)

  // The grid is cleared every frame in Go's ensure(), so it needs no carried state.
  var cells = new Array(dotRows * dotCols)
  for (var z = 0; z < cells.length; z++) cells[z] = 0

  function setDot(x, y, tier) {
    if (x < 0 || x >= dotCols || y < 0 || y >= dotRows) return
    var i = y * dotCols + x
    if (tier > cells[i]) cells[i] = tier
  }

  for (var ax = x0; ax < x0 + span; ax++) setDot(ax, axisY, 1)

  var env = 0
  for (var b = 0; b < bands.length; b++) env += Math.max(0, Math.min(1, bands[b]))
  if (bands.length > 0) env /= bands.length

  // Go reads elapsed seconds as frame * TickAnim; here the render tick is 42.7 ms.
  var t = d.frame * 0.0427
  var halfBars = (barCount - 1) / 2

  for (var i = 0; i < barCount; i++) {
    var distance = halfBars > 0 ? Math.abs(i - halfBars) / halfBars : 0
    var wobble = 0.4 + 0.6 * Math.abs(Math.sin(t * 4.6 + i * 0.42) * Math.sin(t * 1.9 - i * 0.13))
    var amplitude = dotRows * 0.80 * (1 - distance * 0.55) * (0.3 + 0.7 * env) * (0.35 + 0.65 * wobble)
    var radius = Math.min(maxRadius, Math.max(1, Math.round(amplitude)))
    var bx = x0 + i * 2 + 1

    for (var y = axisY - radius; y <= axisY + radius; y++) {
      setDot(bx, y, Math.abs(y - axisY) / radius >= 0.75 ? 3 : 2)
    }
  }

  var tiers = H.specTiers(d)

  ctx.save()
  ctx.font = "bold 10px monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"

  for (var row = 0; row < numRows; row++) {
    var cy = row * charH + charH / 2
    for (var col = 0; col < numCols; col++) {
      var bits = 0, cellTag = -1
      for (var dr = 0; dr < 4; dr++) {
        for (var dc = 0; dc < 2; dc++) {
          var tier = cells[(row * 4 + dr) * dotCols + col * 2 + dc]
          if (tier === 0) continue
          bits |= BRAILLE_BIT[dr][dc]
          if (tier - 1 > cellTag) cellTag = tier - 1
        }
      }
      if (bits === 0) continue
      ctx.fillStyle = tiers[cellTag < 0 ? 0 : cellTag]
      ctx.fillText(String.fromCharCode(0x2800 + bits), col * charW + charW / 2, cy)
    }
  }

  ctx.restore()
}

// Mosaic — exact cliamp vis_mosaic.go: static heatmap of shade-block tiles that
// ignite in place when their assigned band crosses a per-cell threshold
.pragma library
.import "helpers.js" as H

var CELL_W = 2    // characters per tile
var CELL_GAP = 1  // characters between tiles
var DECAY = 0.88

// Discrete brightness tiers. tier -1 renders as spaces so unlit tiles vanish.
var LEVELS = [
  { glyph: " ", tier: -1 },
  { glyph: "░", tier: 0 },
  { glyph: "▒", tier: 0 },
  { glyph: "▓", tier: 0 },
  { glyph: "█", tier: 0 },
  { glyph: "█", tier: 1 },
  { glyph: "█", tier: 2 }
]

function levelFor(intensity) {
  if (intensity >= 0.85) return LEVELS[6]
  if (intensity >= 0.65) return LEVELS[5]
  if (intensity >= 0.45) return LEVELS[4]
  if (intensity >= 0.28) return LEVELS[3]
  if (intensity >= 0.15) return LEVELS[2]
  if (intensity >= 0.05) return LEVELS[1]
  return LEVELS[0]
}

function tileCount(panelWidth) {
  if (panelWidth < CELL_W) return 0
  return Math.floor((panelWidth + CELL_GAP) / (CELL_W + CELL_GAP))
}

// Each cell is wired to a band biased by its row (top treble, bottom bass) with a
// small jitter, and to a threshold in [0.04, 0.78] so lit density rises with loudness.
function ensureGrid(s, rows, tiles, bandCount) {
  if (s.mosaicRows === rows && s.mosaicTiles === tiles && s.mosaicCells
      && s.mosaicCells.length === rows * tiles) return
  s.mosaicRows = rows
  s.mosaicTiles = tiles
  s.mosaicCells = new Array(rows * tiles)

  var rng = { v: 0xC1AB1A10 }
  for (var r = 0; r < rows; r++) {
    var baseBand = rows > 1 ? Math.floor((rows - 1 - r) * (bandCount - 1) / (rows - 1))
                            : Math.floor(bandCount / 2)
    for (var c = 0; c < tiles; c++) {
      var jitter = (H.lcgRng(rng) >>> 16) % 5 - 2
      var band = Math.max(0, Math.min(bandCount - 1, baseBand + jitter))
      s.mosaicCells[r * tiles + c] = {
        bandIdx: band,
        threshold: 0.04 + H.lcgRand01(rng) * 0.74,
        value: 0
      }
    }
  }
}

// vis_mosaic.go OnEnter. ensureGrid reseeds from a fixed constant, so the rebuilt
// grid is identical — what dropping it actually buys is tile intensities back at
// zero, so entering the mode fades up from dark instead of resuming mid-bright.
function onEnter(state) {
  state.mosaicCells = null
  state.mosaicRows = 0
  state.mosaicTiles = 0
}

function render(ctx, d) {
  var bands = d.bands, w = d.width, h = d.height

  var charW = 6
  var charH = 10
  var numCols = Math.floor(w / charW)
  var numRows = Math.floor(h / charH)
  var tiles = tileCount(numCols)
  if (numRows < 1 || tiles < 1) return

  var s = d.state
  ensureGrid(s, numRows, tiles, bands.length || 24)
  var cells = s.mosaicCells

  // Ignite above threshold, then decay in place. Silence just decays.
  for (var i = 0; i < cells.length; i++) {
    var cell = cells[i]
    var level = bands.length ? (bands[cell.bandIdx] || 0) : 0
    if (level > cell.threshold) {
      var ignited = Math.min(1.05, level)
      if (ignited > cell.value) cell.value = ignited
    }
    cell.value *= DECAY
    if (cell.value < 0.001) cell.value = 0
  }

  var tone = H.playerTiers(d)

  ctx.save()
  ctx.font = "bold 10px monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"

  for (var r = 0; r < numRows; r++) {
    var cy = r * charH + charH / 2
    for (var t = 0; t < tiles; t++) {
      var lvl = levelFor(cells[r * tiles + t].value)
      if (lvl.tier < 0) continue
      ctx.fillStyle = tone[lvl.tier]
      for (var k = 0; k < CELL_W; k++) {
        ctx.fillText(lvl.glyph, (t * (CELL_W + CELL_GAP) + k) * charW + charW / 2, cy)
      }
    }
  }

  ctx.restore()
}

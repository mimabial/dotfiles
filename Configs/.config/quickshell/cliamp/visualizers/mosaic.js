.pragma library
.import "helpers.js" as VisualizerHelpers

var CELL_CHARS = 2
var CELL_GAP_CHARS = 1
var DECAY = 0.88

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
  if (panelWidth < CELL_CHARS) return 0
  return Math.floor((panelWidth + CELL_GAP_CHARS) / (CELL_CHARS + CELL_GAP_CHARS))
}

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
      var jitter = (VisualizerHelpers.lcgRng(rng) >>> 16) % 5 - 2
      var band = Math.max(0, Math.min(bandCount - 1, baseBand + jitter))
      s.mosaicCells[r * tiles + c] = {
        bandIdx: band,
        threshold: 0.04 + VisualizerHelpers.lcgRand01(rng) * 0.74,
        value: 0
      }
    }
  }
}

function onEnter(state) {
  state.mosaicCells = null
  state.mosaicRows = 0
  state.mosaicTiles = 0
}

function render(canvas, frameData) {
  var bands = frameData.bands, width = frameData.width, height = frameData.height

  var charW = 6
  var charH = 10
  var numCols = Math.floor(width / charW)
  var numRows = Math.floor(height / charH)
  var tiles = tileCount(numCols)
  if (numRows < 1 || tiles < 1) return

  var animationState = frameData.state
  ensureGrid(animationState, numRows, tiles, bands.length || 24)
  var cells = animationState.mosaicCells

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

  var tone = VisualizerHelpers.playerTiers(frameData)

  canvas.save()
  canvas.font = "bold 10px monospace"
  canvas.textAlign = "center"
  canvas.textBaseline = "middle"

  for (var r = 0; r < numRows; r++) {
    var cy = r * charH + charH / 2
    for (var t = 0; t < tiles; t++) {
      var lvl = levelFor(cells[r * tiles + t].value)
      if (lvl.tier < 0) continue
      canvas.fillStyle = tone[lvl.tier]
      for (var k = 0; k < CELL_CHARS; k++) {
        canvas.fillText(lvl.glyph, (t * (CELL_CHARS + CELL_GAP_CHARS) + k) * charW + charW / 2, cy)
      }
    }
  }

  canvas.restore()
}

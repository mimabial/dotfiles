.pragma library
.import "helpers.js" as VisualizerHelpers

var HASH_WORD = 0x100000000, HASH_HALF_WORD = 0x10000, HASH_BUCKETS = 10000
var HASH_MULTIPLIER_LOW = 0x7197344b, HASH_MULTIPLIER_HIGH = 0x45d9f3b3
var LINE_HEIGHT = 1.25

function bitHash(band, row, col) {
  var value = band * 7919 + row * 6271 + col * 3037 + Math.floor((row * 3 + col) / 3) * 104729
  var high = Math.floor(value / HASH_WORD) >>> 0, low = value >>> 0
  low = (low ^ (low >>> 16) ^ (high << 16)) >>> 0
  high = (high ^ (high >>> 16)) >>> 0
  var lower = low & (HASH_HALF_WORD - 1), upper = low >>> 16
  var product = lower * (HASH_MULTIPLIER_LOW & (HASH_HALF_WORD - 1))
  var cross = (product >>> 16) + upper * (HASH_MULTIPLIER_LOW & (HASH_HALF_WORD - 1)) + lower * (HASH_MULTIPLIER_LOW >>> 16)
  high = (Math.imul(high, HASH_MULTIPLIER_LOW) + Math.imul(low, HASH_MULTIPLIER_HIGH)
    + upper * (HASH_MULTIPLIER_LOW >>> 16) + Math.floor(cross / HASH_HALF_WORD)) >>> 0
  low = Math.imul(low, HASH_MULTIPLIER_LOW) >>> 0
  low = (low ^ (low >>> 16) ^ (high << 16)) >>> 0
  high = (high ^ (high >>> 16)) >>> 0
  return ((high * (HASH_WORD % HASH_BUCKETS) + low) % HASH_BUCKETS) / HASH_BUCKETS
}

function render(canvas, frameData) {
  var width = frameData.width, height = frameData.height, fontSize = frameData.fontSize
  if (width <= 0 || height <= 0 || fontSize <= 0) return

  canvas.save()
  canvas.font = fontSize + "px monospace"
  canvas.textAlign = "center"
  canvas.textBaseline = "middle"
  var charW = canvas.measureText("0").width, charH = fontSize * LINE_HEIGHT
  var cols = Math.floor(width / charW), rows = Math.floor(height / charH)
  if (cols < 1 || rows < 1) { canvas.restore(); return }

  var animationState = frameData.state.binary
  if (!animationState) animationState = frameData.state.binary = { clock: {}, frame: 0 }
  var ticks = VisualizerHelpers.cliampTicks(animationState.clock)
  if (frameData.playing) animationState.frame += ticks

  var bands = VisualizerHelpers.cliampBands(frameData.playing ? frameData.bands : [], frameData.bandEdges)
  var tiers = VisualizerHelpers.specTiers(frameData)
  var visible = Math.min(bands.length, cols), gaps = Math.min(visible - 1, cols - visible)
  var bandCols = cols - gaps, base = Math.floor(bandCols / visible), extra = bandCols % visible
  var offsetX = (width - cols * charW) / 2, offsetY = (height - rows * charH) / 2

  for (var b = 0, col = 0; b < visible; b++) {
    var energy = bands[b], bandWidth = base + (b < extra ? 1 : 0)
    var speed = Math.max(1, 4 - Math.floor(energy * 3))
    var scroll = Math.floor(animationState.frame / speed)
    for (var row = 0; row < rows; row++) {
      for (var c = 0; c < bandWidth; c++) {
        var one = bitHash(b, row + scroll, col + c) < energy * 0.6 + 0.15
        var tag = one && energy > 0.4 ? 2 : one || energy > 0.3 ? 1 : 0
        canvas.fillStyle = tiers[tag]
        canvas.fillText(one ? "1" : "0", offsetX + (col + c + 0.5) * charW, offsetY + (row + 0.5) * charH)
      }
    }
    col += bandWidth
    if (b < visible - 1 && Math.floor((b + 1) * gaps / (visible - 1)) > Math.floor(b * gaps / (visible - 1))) col++
  }
  canvas.restore()
}

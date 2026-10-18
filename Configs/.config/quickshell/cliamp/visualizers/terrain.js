.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, height = frameData.height, width = frameData.width
  var frame = Math.floor(frameData.frame)

  var charW = 6
  var dotCols = Math.floor(width / charW) * 2
  if (dotCols < 2 || height < 1) return

  var animationState = frameData.state
  if (!animationState.terrainBuf || animationState.terrainBuf.length !== dotCols) {
    var old = animationState.terrainBuf || []
    var next = new Array(dotCols)
    for (var i = 0; i < dotCols; i++) next[i] = 0
    var keep = Math.min(old.length, dotCols)
    for (var k = 0; k < keep; k++) next[dotCols - keep + k] = old[old.length - keep + k]
    animationState.terrainBuf = next
  }
  var buf = animationState.terrainBuf

  for (var x = 0; x < dotCols - 2; x++) buf[x] = buf[x + 2]

  var avg = 0
  for (var b = 0; b < bands.length; b++) avg += bands[b]
  avg /= Math.max(1, bands.length)
  buf[dotCols - 2] = Math.min(1.0, avg + VisualizerHelpers.scatterHash(0, 0, 0, frame) * 0.12)
  buf[dotCols - 1] = Math.min(1.0, avg + VisualizerHelpers.scatterHash(0, 0, 1, frame) * 0.12)

  var tops = new Array(dotCols)
  for (var t = 0; t < dotCols; t++) tops[t] = height - 1 - Math.floor(buf[t] * (height - 1))

  var ramp = VisualizerHelpers.playerTierRamp(frameData, height)
  var colW = width / dotCols
  for (var y = 0; y < height; y++) {
    canvas.fillStyle = ramp[height - 1 - y]
    for (var c = 0, run = -1; c <= dotCols; c++) {
      if (c < dotCols && tops[c] <= y) {
        if (run < 0) run = c
      } else if (run >= 0) {
        canvas.fillRect(run * colW, y, (c - run) * colW, 1)
        run = -1
      }
    }
  }
}

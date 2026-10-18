.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, height = frameData.height, count = frameData.count, barW = frameData.barW, gap = frameData.gap
  var ramp = VisualizerHelpers.playerTierRamp(frameData, height), heights = new Array(count)
  for (var i = 0; i < count; i++) heights[i] = Math.round((frameData.playing ? (bands[i] || 0) : 0) * height)
  for (var y = 0; y < height; y++) {
    canvas.fillStyle = ramp[y]
    for (var b = 0; b < count; b++) {
      if (heights[b] > y) canvas.fillRect(b * (barW + gap), height - 1 - y, barW, 1)
    }
  }
}

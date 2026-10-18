.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, height = frameData.height, width = frameData.width, count = frameData.count, barW = frameData.barW, gap = frameData.gap
  var rowUnit = 4
  var ramp = VisualizerHelpers.playerTierRamp(frameData, height)
  for (var i = 0; i < count; i++) {
    var level = frameData.playing ? (bands[i] || 0) : 0
    var x = i * (barW + gap)
    for (var sy = 0; sy < height; sy += rowUnit) {
      var rowThreshold = (height - 1 - sy) / height
      if (level <= rowThreshold) continue
      canvas.fillStyle = ramp[height - 1 - sy]
      canvas.fillRect(x, sy + rowUnit / 2, barW, rowUnit / 2)
    }
  }
}

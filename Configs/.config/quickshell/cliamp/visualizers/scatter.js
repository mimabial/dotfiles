.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, height = frameData.height, count = frameData.count, barW = frameData.barW, gap = frameData.gap, S = 2
  var ramp = VisualizerHelpers.playerTierRamp(frameData, height)
  for (var sy = 0; sy < height; sy += S) {
    canvas.fillStyle = ramp[height - 1 - sy]
    var gravity = 0.5 + 0.5 * sy / height
    for (var sp = 0; sp < count; sp++) {
      var val = frameData.playing ? (bands[sp] || 0) : 0
      var threshold = val * val * gravity
      var spX = sp * (barW + gap)
      for (var sx = 0; sx < barW; sx += S) {
        if (VisualizerHelpers.scatterHash(sp, Math.floor(sy / S), Math.floor(sx / S), frameData.frame) < threshold) {
          canvas.fillRect(spX + sx, sy, S, S)
        }
      }
    }
  }
}

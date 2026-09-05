// Peaks — vis_classic_peak.go: physics-based falling caps
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands, h = d.height, count = d.count, barW = d.barW, gap = d.gap
  var s = d.state
  if (!s.peakPos || s.peakPos.length !== count) {
    s.peakPos = new Array(count).fill(0)
    s.peakVel = new Array(count).fill(0)
    s.peakHold = new Array(count).fill(0)
  }
  var peakPos = s.peakPos, peakVel = s.peakVel, peakHold = s.peakHold
  var dt = 0.016, gravity = 9.5, launchBase = 0.8, launchGain = 1.4, launchMax = 1.7, apexHold = 0.08
  var levels = new Array(count), heights = new Array(count)
  for (var p = 0; p < count; p++) {
    var level = levels[p] = d.playing ? (bands[p] || 0) : 0
    heights[p] = Math.round(level * h)
    if (peakVel[p] === 0 && peakPos[p] <= level + 0.01) {
      if (level > peakPos[p]) {
        var delta = level - peakPos[p]
        peakPos[p] = level
        peakVel[p] = Math.min(launchMax, launchBase + launchGain * delta)
        peakHold[p] = 0
      }
    }
    if (peakHold[p] > 0) {
      peakHold[p] = Math.max(0, peakHold[p] - dt)
    } else {
      var prevVel = peakVel[p]
      peakPos[p] += peakVel[p] * dt
      peakVel[p] -= gravity * dt
      if (peakPos[p] > 1.0) peakPos[p] = 1.0
      if (prevVel > 0 && peakVel[p] <= 0 && peakPos[p] > level + 0.01) {
        peakVel[p] = 0
        peakHold[p] = apexHold
      }
      if (peakPos[p] <= level) {
        peakPos[p] = level
        peakVel[p] = 0
        peakHold[p] = 0
      }
    }
  }
  // Rows outer, bars inner: the colour depends only on the row, so all 24 bars share one
  // fillStyle assignment per row instead of one per pixel.
  var ramp = H.specRamp(d, h)
  for (var y = 0; y < h; y++) {
    ctx.fillStyle = ramp[y]
    for (var b = 0; b < count; b++) {
      if (heights[b] > y) ctx.fillRect(b * (barW + gap), h - 1 - y, barW, 1)
    }
  }
  ctx.fillStyle = H.rgba(d.foreground, 0.95)
  for (var c = 0; c < count; c++) {
    if (peakPos[c] > levels[c] + 0.01) ctx.fillRect(c * (barW + gap), h - Math.round(peakPos[c] * h), barW, 2)
  }
}

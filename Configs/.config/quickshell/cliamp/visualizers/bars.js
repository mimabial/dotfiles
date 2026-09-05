// Bars — vis_bars.go: smooth fractional blocks
.pragma library
.import "helpers.js" as H

// Rows outer, bars inner: the colour depends only on the row, so all 24 bars share one
// fillStyle assignment per row instead of one per pixel.
function render(ctx, d) {
  var bands = d.bands, h = d.height, count = d.count, barW = d.barW, gap = d.gap
  var ramp = H.specRamp(d, h), heights = new Array(count)
  for (var i = 0; i < count; i++) heights[i] = Math.round((d.playing ? (bands[i] || 0) : 0) * h)
  for (var y = 0; y < h; y++) {
    ctx.fillStyle = ramp[y]
    for (var b = 0; b < count; b++) {
      if (heights[b] > y) ctx.fillRect(b * (barW + gap), h - 1 - y, barW, 1)
    }
  }
}

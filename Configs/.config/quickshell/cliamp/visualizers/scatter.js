// Scatter — vis_scatter.go: density = bands² × gravity bias
.pragma library
.import "helpers.js" as H

// Rows outer, bands inner: the colour and the gravity bias depend only on the row, so
// each is computed once per row instead of once per dot.
function render(ctx, d) {
  var bands = d.bands, h = d.height, count = d.count, barW = d.barW, gap = d.gap, S = 2
  var ramp = H.specTierRamp(d, h)
  for (var sy = 0; sy < h; sy += S) {
    ctx.fillStyle = ramp[h - 1 - sy]
    var gravity = 0.5 + 0.5 * sy / h
    for (var sp = 0; sp < count; sp++) {
      var val = d.playing ? (bands[sp] || 0) : 0
      var threshold = val * val * gravity
      var spX = sp * (barW + gap)
      for (var sx = 0; sx < barW; sx += S) {
        if (H.scatterHash(sp, Math.floor(sy / S), Math.floor(sx / S), d.frame) < threshold) {
          ctx.fillRect(spX + sx, sy, S, S)
        }
      }
    }
  }
}

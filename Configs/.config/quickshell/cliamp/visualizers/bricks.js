// Port of cliamp vis_bricks.go, whose ▄ fills only the bottom half of each row.
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands, h = d.height, w = d.width, count = d.count, barW = d.barW, gap = d.gap
  var rowUnit = 4
  var ramp = H.playerTierRamp(d, h)
  for (var i = 0; i < count; i++) {
    var level = d.playing ? (bands[i] || 0) : 0
    var x = i * (barW + gap)
    for (var sy = 0; sy < h; sy += rowUnit) {
      var rowThreshold = (h - 1 - sy) / h
      if (level <= rowThreshold) continue
      ctx.fillStyle = ramp[h - 1 - sy]
      ctx.fillRect(x, sy + rowUnit / 2, barW, rowUnit / 2)
    }
  }
}

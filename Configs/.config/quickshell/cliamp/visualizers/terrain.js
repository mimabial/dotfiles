// Terrain — exact cliamp vis_terrain.go: a scrolling ridge silhouette whose height
// is the mean spectrum energy, new dot columns entering from the right
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands, h = d.height, w = d.width
  var frame = Math.floor(d.frame)

  var charW = 6
  var dotCols = Math.floor(w / charW) * 2
  if (dotCols < 2 || h < 1) return

  var s = d.state
  if (!s.terrainBuf || s.terrainBuf.length !== dotCols) {
    var old = s.terrainBuf || []
    var next = new Array(dotCols)
    for (var i = 0; i < dotCols; i++) next[i] = 0
    var keep = Math.min(old.length, dotCols)
    for (var k = 0; k < keep; k++) next[dotCols - keep + k] = old[old.length - keep + k]
    s.terrainBuf = next
  }
  var buf = s.terrainBuf

  // Scroll left two dot columns per frame, then push two fresh heights in on the right.
  for (var x = 0; x < dotCols - 2; x++) buf[x] = buf[x + 2]

  var avg = 0
  for (var b = 0; b < bands.length; b++) avg += bands[b]
  avg /= Math.max(1, bands.length)
  buf[dotCols - 2] = Math.min(1.0, avg + H.scatterHash(0, 0, 0, frame) * 0.12)
  buf[dotCols - 1] = Math.min(1.0, avg + H.scatterHash(0, 0, 1, frame) * 0.12)

  var tops = new Array(dotCols)
  for (var t = 0; t < dotCols; t++) tops[t] = h - 1 - Math.floor(buf[t] * (h - 1))

  // Rows outer: the tier depends only on the row, and a row's filled columns are mostly
  // contiguous, so this is one fillStyle and a handful of spans per row.
  var ramp = H.playerTierRamp(d, h)
  var colW = w / dotCols
  for (var y = 0; y < h; y++) {
    ctx.fillStyle = ramp[h - 1 - y]
    for (var c = 0, run = -1; c <= dotCols; c++) {
      if (c < dotCols && tops[c] <= y) {
        if (run < 0) run = c
      } else if (run >= 0) {
        ctx.fillRect(run * colW, y, (c - run) * colW, 1)
        run = -1
      }
    }
  }
}

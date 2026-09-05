// Terrain — vis_terrain.go: scrolling buffer, new data enters right
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands, h = d.height, w = d.width, count = d.count, frame = d.frame
  var s = d.state
  if (!s.terrainBuf || s.terrainBuf.length !== w) s.terrainBuf = new Array(w).fill(0.1)
  var buf = s.terrainBuf

  // Scroll left
  for (var x = 0; x < w - 1; x++) buf[x] = buf[x + 1]

  // New averaged spectrum value enters from right
  var avg = 0
  for (var i = 0; i < count; i++) avg += (bands[i] || 0)
  avg /= count
  var noise = H.scatterHash(0, 0, w - 1, Math.floor(frame / 3)) * 0.15
  buf[w - 1] = d.playing ? Math.max(0.02, avg + noise - 0.05) : Math.max(0.0, buf[w - 1] * 0.9 - 0.01)

  // Render filled terrain (green valleys, yellow slopes, red peaks). Rows outer: the
  // colour depends only on the row, and a row's filled columns are mostly contiguous, so
  // this is one fillStyle and a handful of spans per row rather than w*h single pixels.
  var tops = new Array(w)
  for (var i2 = 0; i2 < w; i2++) tops[i2] = h - 1 - Math.floor(buf[i2] * (h - 1))
  var ramp = H.specRamp(d, h)
  for (var y = 0; y < h; y++) {
    ctx.fillStyle = ramp[h - 1 - y]
    for (var x2 = 0, run = -1; x2 <= w; x2++) {
      if (x2 < w && tops[x2] <= y) { if (run < 0) run = x2 }
      else if (run >= 0) { ctx.fillRect(run, y, x2 - run, 1); run = -1 }
    }
  }
}

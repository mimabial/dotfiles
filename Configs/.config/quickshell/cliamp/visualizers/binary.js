// Binary — two-timescale digit rain. A slow loudness envelope sets density and scroll
// rate, bands set per-column activity, beats nudge the stream forward a row. Glyphs are
// written once when a row is created and never revisited, so the stream scrolls instead
// of boiling in place.
.pragma library
.import "helpers.js" as H

function makeRow(rng, cols, colEnergy, density, hot) {
  var chars = "", levels = new Array(cols)
  for (var c = 0; c < cols; c++) {
    var energy = colEnergy[c] || 0
    levels[c] = energy
    chars += H.lcgRand01(rng) < (density * 0.30 + energy * 0.55) ? "1" : "0"
  }
  return { chars: chars, levels: levels, hot: hot }
}

function render(ctx, d) {
  var w = d.width, h = d.height
  var charW = 6, charH = 9
  var cols = Math.floor(w / charW), rows = Math.floor(h / charH)
  if (cols < 1 || rows < 1) return

  var st = d.state.binaryStream
  if (!st || st.cols !== cols || st.rows !== rows) {
    st = d.state.binaryStream = { cols: cols, rows: rows, grid: new Array(rows), head: 0,
                                  offset: 0, frame: d.frame, density: 0, beat: 0,
                                  rng: { v: 0x2545f491 } }
    var quiet = new Array(cols)
    for (var q = 0; q < cols; q++) quiet[q] = 0
    for (var r = 0; r < rows; r++) st.grid[r] = makeRow(st.rng, cols, quiet, 0, false)
  }

  // d.frame advances once per 42.7 ms render tick and stalls while paused, so a frame
  // delta is elapsed wall-clock time and a paused stream holds its last state.
  var elapsed = Math.max(0, Math.min(8, d.frame - st.frame)) * 0.0427
  st.frame = d.frame

  var bands = d.playing ? (d.bands || []) : []
  var loud = Math.min(1, H.bandAvg(bands, 0, bands.length) * 1.6)
  st.density += (loud - st.density) * (1 - Math.exp(-elapsed / 0.6))

  var colEnergy = H.resampleBandsLinear(bands, cols)
  if (!colEnergy.length) {
    colEnergy = new Array(cols)
    for (var e = 0; e < cols; e++) colEnergy[e] = 0
  }

  var beat = d.beatDrop || 0
  var kick = beat > 0.55 && st.beat <= 0.55
  st.beat = beat

  // Beats nudge a free-running scroll rather than clocking it: the detector gates on
  // 20-47 Hz, so advancing only on beats would freeze the stream on thin material.
  st.offset += (d.playing ? elapsed * (4.2 + st.density * 10.5) : 0) + (kick ? 1 : 0)
  var steps = Math.floor(st.offset)
  st.offset -= steps
  var advances = Math.min(rows, steps)
  for (var a = 0; a < advances; a++) {
    st.head = (st.head + rows - 1) % rows
    st.grid[st.head] = makeRow(st.rng, cols, colEnergy, st.density, kick && a === advances - 1)
  }

  ctx.fillStyle = H.rgba(d.surface, 0.2)
  ctx.fillRect(0, 0, w, h)
  ctx.font = "8px monospace"
  ctx.textBaseline = "top"

  for (var i = 0; i < rows; i++) {
    var row = st.grid[(st.head + i) % rows]
    var fade = 1 - i / rows
    var strong = H.rgba(d.accent, 0.40 + 0.55 * fade)
    var weak = H.rgba(d.accent, 0.20 + 0.28 * fade)
    var cold = H.rgba(d.dim, 0.32 * fade)
    var crest = i === 0 && row.hot ? H.rgba(d.foreground, 0.95 * Math.max(beat, 0.4)) : ""
    var y = i * charH
    for (var c = 0; c < cols; c++) {
      var on = row.chars.charAt(c) === "1"
      ctx.fillStyle = !on ? cold : crest ? crest : row.levels[c] > 0.35 ? strong : weak
      ctx.fillText(on ? "1" : "0", c * charW, y)
    }
  }
}

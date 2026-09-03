// Correlation — broadcast phase correlation meter: +1 mono, 0 uncorrelated, -1 inverted.
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var stereo = d.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var w = d.width, h = d.height, st = d.state, pal = d.colors || []
  var pad = 14
  var trackX = pad, trackW = Math.max(1, w - pad * 2)
  var trackY = Math.round(h * 0.36), trackH = Math.max(6, Math.round(h * 0.34))
  var mid = trackX + trackW / 2

  function posFor(value) { return trackX + trackW * (value + 1) / 2 }

  // Zero-mean Pearson over the window. Audio is AC-coupled, so the means sit at ~0 and
  // the raw sums stand in for the centred products.
  var n = Math.min(left.length, right.length)
  var sumLR = 0, sumLL = 0, sumRR = 0
  for (var i = 0; i < n; i++) {
    var lv = Number(left[i]) || 0, rv = Number(right[i]) || 0
    sumLR += lv * rv; sumLL += lv * lv; sumRR += rv * rv
  }
  var denom = Math.sqrt(sumLL * sumRR)
  var target = (d.playing && denom > 1e-9) ? Math.max(-1, Math.min(1, sumLR / denom)) : 0

  var now = Date.now()
  if (st.corrValue === undefined) { st.corrValue = 0; st.corrHold = 0; st.corrLast = now }
  var dt = Math.min(0.12, Math.max(0.001, (now - st.corrLast) / 1000))
  st.corrLast = now
  // A 10.7ms window on its own is far too jumpy to read, so the needle is damped and the
  // hold falls instantly but recovers slowly -- brief phase dips are the whole point.
  st.corrValue += (target - st.corrValue) * (1 - Math.exp(-dt / 0.30))
  st.corrHold = Math.min(st.corrValue, st.corrHold + 0.35 * dt)

  var value = st.corrValue
  var danger = pal[1] || d.accent

  ctx.fillStyle = H.rgba(d.foreground, 0.07)
  ctx.fillRect(trackX, trackY, trackW, trackH)

  var ticks = [-1, -0.5, 0, 0.5, 1]
  ctx.lineWidth = 1
  for (var t = 0; t < ticks.length; t++) {
    var tx = Math.round(posFor(ticks[t])) + 0.5
    ctx.strokeStyle = H.rgba(d.foreground, ticks[t] === 0 ? 0.30 : 0.12)
    ctx.beginPath(); ctx.moveTo(tx, trackY); ctx.lineTo(tx, trackY + trackH); ctx.stroke()
  }

  // Filled from the centre, because distance from zero is the reading. The negative half
  // gets its own hue: that is the half that cancels to nothing when someone plays it mono.
  var valueX = posFor(value)
  var fillW = Math.abs(valueX - mid)
  if (fillW >= 1) {
    var tint = value < 0 ? danger : d.accent
    var gradient = ctx.createLinearGradient(mid, 0, valueX, 0)
    gradient.addColorStop(0, H.rgba(tint, 0.25))
    gradient.addColorStop(1, H.rgba(tint, 0.85))
    ctx.fillStyle = gradient
    ctx.fillRect(Math.min(mid, valueX), trackY, fillW, trackH)
  }

  ctx.fillStyle = H.rgba(st.corrHold < 0 ? danger : d.dim, 0.9)
  ctx.fillRect(Math.round(posFor(st.corrHold)), trackY - 2, 1, trackH + 4)

  ctx.fillStyle = H.rgba(d.foreground, 0.95)
  ctx.fillRect(Math.round(valueX) - 1, trackY - 2, 2, trackH + 4)

  ctx.font = "7px monospace"
  ctx.fillStyle = H.rgba(d.dim, 0.9)
  ctx.textAlign = "left"; ctx.fillText("OUT OF PHASE", trackX, trackY - 5)
  ctx.textAlign = "right"; ctx.fillText("MONO", trackX + trackW, trackY - 5)
  ctx.textAlign = "center"
  ctx.fillStyle = H.rgba(d.foreground, 0.95)
  ctx.fillText((value >= 0 ? "+" : "") + value.toFixed(2), mid, trackY - 5)

  ctx.fillStyle = H.rgba(d.dim, 0.8)
  ctx.fillText("-1", posFor(-1), h - 1)
  ctx.fillText("0", mid, h - 1)
  ctx.fillText("+1", posFor(1), h - 1)
}

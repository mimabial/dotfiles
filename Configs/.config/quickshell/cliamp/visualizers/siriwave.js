// Siri Wave — Silky smooth, uncropped Apple fluid wave with acoustic energy modulation
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var bands = d.bands || []
  var w = d.width, h = d.height
  var isPlaying = d.playing
  var midY = h / 2.0

  var bass = H.bandAvg(bands, 0, 5)
  var mids = H.bandAvg(bands, 5, 14)
  var highs = H.bandAvg(bands, 14, 24)
  var totalEnergy = bass * 0.5 + mids * 0.35 + highs * 0.15
  var beatDrop = d.beatDrop || 0

  if (!isPlaying || totalEnergy < 0.005) {
    ctx.strokeStyle = H.rgba(d.dim, 0.35)
    ctx.lineWidth = 1.0
    ctx.beginPath()
    ctx.moveTo(0, midY)
    ctx.lineTo(w, midY)
    ctx.stroke()
    return
  }

  var maxSafeAmp = h * 0.36
  var bassAmp = Math.min(maxSafeAmp, (h * 0.08) + (bass * (h * 0.24)) + (beatDrop * (h * 0.08)))
  var midsAmp = Math.min(maxSafeAmp * 0.9, (h * 0.06) + (mids * (h * 0.22)))
  var highsAmp = Math.min(maxSafeAmp * 0.8, (h * 0.05) + (highs * (h * 0.20)))

  // Integrate the phase instead of frame * speed. speed changes with the audio every
  // paint, and frame never resets, so that product jumps by frame * dspeed -- a rotation
  // proportional to uptime. Rate is rad/s: the old per-frame value * 23.4 ticks/s.
  var st = d.state, now = Date.now()
  if (st.siriPhase === undefined) { st.siriPhase = 0; st.siriLast = now }
  var dt = Math.min(0.12, Math.max(0.001, (now - st.siriLast) / 1000))
  st.siriLast = now
  st.siriPhase += (0.820 + totalEnergy * 0.820) * dt
  var phase = st.siriPhase

  // Apple Global Attenuation Formula: (4 / (4 + x^4))^4 on x in [-2, 2]
  function globalAttenuation(x) {
    var x2 = x * x
    var x4 = x2 * x2
    return Math.pow(4.0 / (4.0 + x4), 4.0)
  }

  // Bass, mids and highs take three adjacent hues from the theme's own palette
  // (pink / accent / blue) rather than rotations synthesised off the accent.
  var pal = d.colors || []
  var ribbons = [
    { from: pal[1] || d.accent, to: d.foreground, mix: 0.10, alpha: 0.55, freq: 1.15, speed: 1.0,  phaseOff: 0.0, amp: bassAmp },
    { from: d.accent,           to: d.foreground, mix: 0.15, alpha: 0.50, freq: 1.65, speed: -1.2, phaseOff: 1.4, amp: midsAmp },
    { from: pal[4] || d.dim,    to: d.foreground, mix: 0.10, alpha: 0.45, freq: 2.15, speed: 1.5,  phaseOff: 2.8, amp: highsAmp }
  ]

  for (var c = 0; c < ribbons.length; c++) {
    var rb = ribbons[c]
    var curPhase = phase * rb.speed + rb.phaseOff

    var grad = ctx.createLinearGradient(0, midY - rb.amp, 0, midY + rb.amp * 0.5)
    grad.addColorStop(0, H.mixColor(rb.from, rb.to, rb.mix, rb.alpha))
    grad.addColorStop(1, H.mixColor(rb.from, rb.to, rb.mix, 0.02))

    ctx.fillStyle = grad
    ctx.beginPath()
    ctx.moveTo(0, midY)

    for (var i = 0; i <= w; i += 2) {
      var xNorm = (i / w) * 4.0 - 2.0 // Domain [-2, 2]
      var att = globalAttenuation(xNorm)
      var disp = Math.sin(xNorm * rb.freq * Math.PI + curPhase) * rb.amp * att
      ctx.lineTo(i, midY - disp)
    }

    for (var j = w; j >= 0; j -= 2) {
      var xNormB = (j / w) * 4.0 - 2.0
      var attB = globalAttenuation(xNormB)
      var dispB = Math.sin(xNormB * rb.freq * Math.PI + curPhase) * (rb.amp * 0.28) * attB
      ctx.lineTo(j, midY + dispB)
    }

    ctx.closePath()
    ctx.fill()
  }

  ctx.strokeStyle = H.rgba(d.foreground, 0.95)
  ctx.lineWidth = 2.0
  ctx.beginPath()

  var crestAmp = Math.min(maxSafeAmp, (h * 0.08) + (totalEnergy * (h * 0.25)) + (beatDrop * (h * 0.06)))
  for (var k = 0; k <= w; k += 2) {
    var xk = (k / w) * 4.0 - 2.0
    var attK = globalAttenuation(xk)
    var yDisp = Math.sin(xk * 1.35 * Math.PI + phase) * crestAmp * attK
    var yPos = midY - yDisp

    if (k === 0) ctx.moveTo(k, yPos)
    else ctx.lineTo(k, yPos)
  }
  ctx.stroke()
}

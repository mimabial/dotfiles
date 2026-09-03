// Liquid Silk Plasma — Calibrated harmonic fluid field with edge attenuation and audio-reactive pacing
.pragma library
.import "helpers.js" as H

function smoothSpectrum(state, bands, dt) {
  if (!state.plasmaBands || state.plasmaBands.length !== bands.length)
    state.plasmaBands = bands.slice()
  var temporal = new Array(bands.length), spatial = new Array(bands.length)
  for (var index = 0; index < bands.length; index++) {
    var target = Math.max(0, Math.min(1, Number(bands[index] || 0)))
    var previous = Number(state.plasmaBands[index] || 0)
    var tau = target > previous ? 0.045 : 0.12
    temporal[index] = previous + (target - previous) * (1 - Math.exp(-dt / tau))
  }
  state.plasmaBands = temporal
  for (var band = 0; band < temporal.length; band++) {
    var before = temporal[Math.max(0, band - 1)]
    var after = temporal[Math.min(temporal.length - 1, band + 1)]
    spatial[band] = (before + temporal[band] * 2 + after) / 4
  }
  return spatial
}

function render(ctx, d) {
  var bands = d.bands || []
  var w = d.width, h = d.height
  var isPlaying = d.playing
  var midY = h / 2.0

  var rawBass = H.bandAvg(bands, 0, 7)
  var rawMids = H.bandAvg(bands, 7, 16)
  var rawHighs = H.bandAvg(bands, 16, 24)
  var rawEnergy = rawBass * 0.50 + rawMids * 0.35 + rawHighs * 0.15
  var st = d.state, now = Date.now()
  if (st.plasmaPhase === undefined) { st.plasmaPhase = 0; st.plasmaLast = now }
  var dt = Math.min(0.12, Math.max(0.001, (now - st.plasmaLast) / 1000))
  st.plasmaLast = now

  // Resting state when paused or quiet
  if (!isPlaying || rawEnergy < 0.005) {
    st.plasmaBands = []
    ctx.strokeStyle = H.rgba(d.dim, 0.35)
    ctx.lineWidth = 1.0
    ctx.beginPath()
    ctx.moveTo(0, midY)
    ctx.lineTo(w, midY)
    ctx.stroke()
    return
  }

  // 1. Temporally and spatially smoothed acoustic frequency extraction.
  var smoothBands = smoothSpectrum(st, bands, dt)
  var bass = H.bandAvg(smoothBands, 0, 7)
  var mids = H.bandAvg(smoothBands, 7, 16)
  var highs = H.bandAvg(smoothBands, 16, 24)
  var totalEnergy = bass * 0.50 + mids * 0.35 + highs * 0.15
  var beatDrop = d.beatDrop || 0

  // 2. Controlled Acoustic Pacing (Calm, organic motion that speeds up on energy bursts)
  // Integrated, not frame * speed -- see siriwave.js. Rate is rad/s.
  st.plasmaPhase += (0.234 + totalEnergy * 0.422 + beatDrop * 0.351) * dt
  var phase = st.plasmaPhase

  // Safe vertical envelope so it never clips top or bottom borders
  var maxSafeAmp = h * 0.38
  var bassAmp = Math.min(maxSafeAmp, (h * 0.08) + (bass * (h * 0.22)) + (beatDrop * (h * 0.08)))
  var midsAmp = Math.min(maxSafeAmp * 0.9, (h * 0.06) + (mids * (h * 0.20)))
  var highsAmp = Math.min(maxSafeAmp * 0.8, (h * 0.05) + (highs * (h * 0.18)))

  // Smooth edge attenuation formula so waves taper gracefully to 0 at left and right edges
  function edgeAtt(xNorm) {
    var d = (xNorm - 0.5) * 2.0 // [-1, 1]
    var d2 = d * d
    return Math.max(0.0, 1.0 - d2 * d2)
  }

  // 3. Fluid Harmonic Silk Layers
  // Three adjacent palette hues, same reasoning as siriwave.
  var pal = d.colors || []
  var layers = [
    { amp: bassAmp,  freq: 1.2, speed: 1.0,  phaseOff: 0.0, from: pal[1] || d.accent, to: d.foreground, mix: 0.10, alpha: 0.55 },
    { amp: midsAmp,  freq: 1.8, speed: -0.9, phaseOff: 1.6, from: d.accent,           to: d.dim,        mix: 0.20, alpha: 0.50 },
    { amp: highsAmp, freq: 2.4, speed: 1.3,  phaseOff: 3.2, from: pal[4] || d.dim,    to: d.foreground, mix: 0.20, alpha: 0.45 }
  ]

  for (var l = 0; l < layers.length; l++) {
    var ly = layers[l]
    var curPhase = phase * ly.speed + ly.phaseOff
    var a = (ly.alpha * (0.6 + totalEnergy * 0.4 + beatDrop * 0.2))
    var points = []
    for (var x = 0; x <= w; x++) {
      var xNorm = x / w
      var att = edgeAtt(xNorm)
      var bVal = H.sampleBandLinear(smoothBands, xNorm * (smoothBands.length - 1))
      var s1 = Math.sin(xNorm * Math.PI * 2.0 * ly.freq + curPhase)
      var s2 = Math.sin(xNorm * Math.PI * 4.0 * ly.freq - curPhase * 0.6) * 0.3
      var waveVal = (s1 + s2) * (ly.amp * (0.6 + bVal * 0.6)) * att
      points.push({ x: x, y: midY - waveVal })
    }

    // Under-fill gradient with smooth fade
    ctx.beginPath()
    ctx.moveTo(0, midY)
    for (var point = 0; point < points.length; point++) ctx.lineTo(points[point].x, points[point].y)
    ctx.lineTo(w, midY)
    ctx.closePath()

    var grad = ctx.createLinearGradient(0, midY - ly.amp, 0, midY + ly.amp * 0.6)
    grad.addColorStop(0, H.mixColor(ly.from, ly.to, ly.mix, (a * 0.50).toFixed(2)))
    grad.addColorStop(0.6, H.mixColor(ly.from, ly.to, ly.mix, (a * 0.15).toFixed(2)))
    grad.addColorStop(1, H.mixColor(ly.from, ly.to, ly.mix, 0))

    ctx.fillStyle = grad
    ctx.fill()

    // Glowing Silk Surface Line
    ctx.beginPath()
    for (var surface = 0; surface < points.length; surface++) {
      if (surface === 0) ctx.moveTo(points[surface].x, points[surface].y)
      else ctx.lineTo(points[surface].x, points[surface].y)
    }

    ctx.strokeStyle = H.mixColor(ly.from, d.foreground, Math.min(1, ly.mix + 0.28), (a * 0.95).toFixed(2))
    ctx.lineWidth = l === 0 ? 2.0 : 1.3
    ctx.lineJoin = "round"; ctx.lineCap = "round"
    ctx.stroke()
  }
}

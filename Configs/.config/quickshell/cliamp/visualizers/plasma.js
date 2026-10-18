.pragma library
.import "helpers.js" as VisualizerHelpers

function smoothSpectrum(state, bands, elapsedSeconds) {
  if (!state.plasmaBands || state.plasmaBands.length !== bands.length)
    state.plasmaBands = bands.slice()
  var temporal = new Array(bands.length), spatial = new Array(bands.length)
  for (var index = 0; index < bands.length; index++) {
    var target = Math.max(0, Math.min(1, Number(bands[index] || 0)))
    var previous = Number(state.plasmaBands[index] || 0)
    var tau = target > previous ? 0.045 : 0.12
    temporal[index] = previous + (target - previous) * (1 - Math.exp(-elapsedSeconds / tau))
  }
  state.plasmaBands = temporal
  for (var band = 0; band < temporal.length; band++) {
    var before = temporal[Math.max(0, band - 1)]
    var after = temporal[Math.min(temporal.length - 1, band + 1)]
    spatial[band] = (before + temporal[band] * 2 + after) / 4
  }
  return spatial
}

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height
  var isPlaying = frameData.playing
  var midY = height / 2.0

  var rawBass = VisualizerHelpers.bandAvg(bands, 0, 7)
  var rawMids = VisualizerHelpers.bandAvg(bands, 7, 16)
  var rawHighs = VisualizerHelpers.bandAvg(bands, 16, 24)
  var rawEnergy = rawBass * 0.50 + rawMids * 0.35 + rawHighs * 0.15
  var animationState = frameData.state, now = Date.now()
  if (animationState.plasmaPhase === undefined) { animationState.plasmaPhase = 0; animationState.plasmaLast = now }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.plasmaLast) / 1000))
  animationState.plasmaLast = now

  if (!isPlaying || rawEnergy < 0.005) {
    animationState.plasmaBands = []
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.dim, 0.35)
    canvas.lineWidth = 1.0
    canvas.beginPath()
    canvas.moveTo(0, midY)
    canvas.lineTo(width, midY)
    canvas.stroke()
    return
  }

  var smoothBands = smoothSpectrum(animationState, bands, elapsedSeconds)
  var bass = VisualizerHelpers.bandAvg(smoothBands, 0, 7)
  var mids = VisualizerHelpers.bandAvg(smoothBands, 7, 16)
  var highs = VisualizerHelpers.bandAvg(smoothBands, 16, 24)
  var totalEnergy = bass * 0.50 + mids * 0.35 + highs * 0.15
  var beatDrop = frameData.beatDrop || 0

  animationState.plasmaPhase += (0.234 + totalEnergy * 0.422 + beatDrop * 0.351) * elapsedSeconds
  var phase = animationState.plasmaPhase

  var maxSafeAmp = height * 0.38
  var bassAmp = Math.min(maxSafeAmp, (height * 0.08) + (bass * (height * 0.22)) + (beatDrop * (height * 0.08)))
  var midsAmp = Math.min(maxSafeAmp * 0.9, (height * 0.06) + (mids * (height * 0.20)))
  var highsAmp = Math.min(maxSafeAmp * 0.8, (height * 0.05) + (highs * (height * 0.18)))

  function edgeAtt(xNorm) {
    var centerDistance = (xNorm - 0.5) * 2.0  
    var d2 = centerDistance * centerDistance
    return Math.max(0.0, 1.0 - d2 * d2)
  }

  var palette = frameData.colors || []
  var layers = [
    { amp: bassAmp,  freq: 1.2, speed: 1.0,  phaseOff: 0.0, from: palette[1] || frameData.accent, to: frameData.foreground, mix: 0.10, alpha: 0.55 },
    { amp: midsAmp,  freq: 1.8, speed: -0.9, phaseOff: 1.6, from: frameData.accent,           to: frameData.dim,        mix: 0.20, alpha: 0.50 },
    { amp: highsAmp, freq: 2.4, speed: 1.3,  phaseOff: 3.2, from: palette[4] || frameData.dim,    to: frameData.foreground, mix: 0.20, alpha: 0.45 }
  ]

  for (var l = 0; l < layers.length; l++) {
    var ly = layers[l]
    var curPhase = phase * ly.speed + ly.phaseOff
    var a = (ly.alpha * (0.6 + totalEnergy * 0.4 + beatDrop * 0.2))
    var points = []
    for (var x = 0; x <= width; x++) {
      var xNorm = x / width
      var att = edgeAtt(xNorm)
      var bVal = VisualizerHelpers.sampleBandLinear(smoothBands, xNorm * (smoothBands.length - 1))
      var s1 = Math.sin(xNorm * Math.PI * 2.0 * ly.freq + curPhase)
      var s2 = Math.sin(xNorm * Math.PI * 4.0 * ly.freq - curPhase * 0.6) * 0.3
      var waveVal = (s1 + s2) * (ly.amp * (0.6 + bVal * 0.6)) * att
      points.push({ x: x, y: midY - waveVal })
    }

    canvas.beginPath()
    canvas.moveTo(0, midY)
    for (var point = 0; point < points.length; point++) canvas.lineTo(points[point].x, points[point].y)
    canvas.lineTo(width, midY)
    canvas.closePath()

    var gradient = canvas.createLinearGradient(0, midY - ly.amp, 0, midY + ly.amp * 0.6)
    gradient.addColorStop(0, VisualizerHelpers.mixColor(ly.from, ly.to, ly.mix, (a * 0.50).toFixed(2)))
    gradient.addColorStop(0.6, VisualizerHelpers.mixColor(ly.from, ly.to, ly.mix, (a * 0.15).toFixed(2)))
    gradient.addColorStop(1, VisualizerHelpers.mixColor(ly.from, ly.to, ly.mix, 0))

    canvas.fillStyle = gradient
    canvas.fill()

    canvas.beginPath()
    for (var surface = 0; surface < points.length; surface++) {
      if (surface === 0) canvas.moveTo(points[surface].x, points[surface].y)
      else canvas.lineTo(points[surface].x, points[surface].y)
    }

    canvas.strokeStyle = VisualizerHelpers.mixColor(ly.from, frameData.foreground, Math.min(1, ly.mix + 0.28), (a * 0.95).toFixed(2))
    canvas.lineWidth = l === 0 ? 2.0 : 1.3
    canvas.lineJoin = "round"; canvas.lineCap = "round"
    canvas.stroke()
  }
}

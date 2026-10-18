.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height
  var isPlaying = frameData.playing
  var midY = height / 2.0

  var bass = VisualizerHelpers.bandAvg(bands, 0, 5)
  var mids = VisualizerHelpers.bandAvg(bands, 5, 14)
  var highs = VisualizerHelpers.bandAvg(bands, 14, 24)
  var totalEnergy = bass * 0.5 + mids * 0.35 + highs * 0.15
  var beatDrop = frameData.beatDrop || 0

  if (!isPlaying || totalEnergy < 0.005) {
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.dim, 0.35)
    canvas.lineWidth = 1.0
    canvas.beginPath()
    canvas.moveTo(0, midY)
    canvas.lineTo(width, midY)
    canvas.stroke()
    return
  }

  var maxSafeAmp = height * 0.36
  var bassAmp = Math.min(maxSafeAmp, (height * 0.08) + (bass * (height * 0.24)) + (beatDrop * (height * 0.08)))
  var midsAmp = Math.min(maxSafeAmp * 0.9, (height * 0.06) + (mids * (height * 0.22)))
  var highsAmp = Math.min(maxSafeAmp * 0.8, (height * 0.05) + (highs * (height * 0.20)))

  var animationState = frameData.state, now = Date.now()
  if (animationState.siriPhase === undefined) { animationState.siriPhase = 0; animationState.siriLast = now }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.siriLast) / 1000))
  animationState.siriLast = now
  animationState.siriPhase += (0.820 + totalEnergy * 0.820) * elapsedSeconds
  var phase = animationState.siriPhase

  function globalAttenuation(x) {
    var x2 = x * x
    var x4 = x2 * x2
    return Math.pow(4.0 / (4.0 + x4), 4.0)
  }

  var palette = frameData.colors || []
  var ribbons = [
    { from: palette[1] || frameData.accent, to: frameData.foreground, mix: 0.10, alpha: 0.55, freq: 1.15, speed: 1.0,  phaseOff: 0.0, amp: bassAmp },
    { from: frameData.accent,           to: frameData.foreground, mix: 0.15, alpha: 0.50, freq: 1.65, speed: -1.2, phaseOff: 1.4, amp: midsAmp },
    { from: palette[4] || frameData.dim,    to: frameData.foreground, mix: 0.10, alpha: 0.45, freq: 2.15, speed: 1.5,  phaseOff: 2.8, amp: highsAmp }
  ]

  for (var c = 0; c < ribbons.length; c++) {
    var rb = ribbons[c]
    var curPhase = phase * rb.speed + rb.phaseOff

    var gradient = canvas.createLinearGradient(0, midY - rb.amp, 0, midY + rb.amp * 0.5)
    gradient.addColorStop(0, VisualizerHelpers.mixColor(rb.from, rb.to, rb.mix, rb.alpha))
    gradient.addColorStop(1, VisualizerHelpers.mixColor(rb.from, rb.to, rb.mix, 0.02))

    canvas.fillStyle = gradient
    canvas.beginPath()
    canvas.moveTo(0, midY)

    for (var i = 0; i <= width; i += 2) {
      var xNorm = (i / width) * 4.0 - 2.0  
      var att = globalAttenuation(xNorm)
      var disp = Math.sin(xNorm * rb.freq * Math.PI + curPhase) * rb.amp * att
      canvas.lineTo(i, midY - disp)
    }

    for (var j = width; j >= 0; j -= 2) {
      var xNormB = (j / width) * 4.0 - 2.0
      var attB = globalAttenuation(xNormB)
      var dispB = Math.sin(xNormB * rb.freq * Math.PI + curPhase) * (rb.amp * 0.28) * attB
      canvas.lineTo(j, midY + dispB)
    }

    canvas.closePath()
    canvas.fill()
  }

  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, 0.95)
  canvas.lineWidth = 2.0
  canvas.beginPath()

  var crestAmp = Math.min(maxSafeAmp, (height * 0.08) + (totalEnergy * (height * 0.25)) + (beatDrop * (height * 0.06)))
  for (var k = 0; k <= width; k += 2) {
    var xk = (k / width) * 4.0 - 2.0
    var attK = globalAttenuation(xk)
    var yDisp = Math.sin(xk * 1.35 * Math.PI + phase) * crestAmp * attK
    var yPos = midY - yDisp

    if (k === 0) canvas.moveTo(k, yPos)
    else canvas.lineTo(k, yPos)
  }
  canvas.stroke()
}

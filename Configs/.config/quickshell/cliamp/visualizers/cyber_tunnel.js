.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var cx = width / 2.0, cy = height / 2.0

  var bass = VisualizerHelpers.bandAvg(bands, 0, 5)
  var mids = VisualizerHelpers.bandAvg(bands, 5, 14)
  var highs = VisualizerHelpers.bandAvg(bands, 14, 24)
  var totalEnergy = bass * 0.5 + mids * 0.35 + highs * 0.15
  var beatDrop = frameData.beatDrop || 0

  if (!isPlaying || totalEnergy < 0.005) {
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.dim, 0.35)
    canvas.lineWidth = 1.0
    canvas.beginPath()
    canvas.arc(cx, cy, Math.min(width, height) * 0.20, 0, Math.PI * 2)
    canvas.stroke()
    return
  }

  var animationState = frameData.state, now = Date.now()
  if (animationState.tunnelDepth === undefined) { animationState.tunnelDepth = 0; animationState.tunnelLast = now }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.tunnelLast) / 1000))
  animationState.tunnelLast = now
  animationState.tunnelDepth = (animationState.tunnelDepth + (0.141 + totalEnergy * 0.281 + beatDrop * 0.351) * elapsedSeconds) % 1.0
  var ringCount = 8
  var numSides = 8
  var rotBase = frame * 0.005

  canvas.lineWidth = 0.8
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.20)

  for (var s = 0; s < numSides; s++) {
    var angle = rotBase + (s * (Math.PI * 2 / numSides))
    var outerX = cx + Math.cos(angle) * (width * 0.44)
    var outerY = cy + Math.sin(angle) * (height * 0.44)

    canvas.beginPath()
    canvas.moveTo(cx, cy)
    canvas.lineTo(outerX, outerY)
    canvas.stroke()
  }

  for (var i = 0; i < ringCount; i++) {
    var z = ((i / ringCount) + animationState.tunnelDepth) % 1.0
    var scale = Math.pow(z, 2.0)
    if (scale < 0.03) continue

    var bandIndex = Math.min(bands.length - 1, Math.floor((1.0 - z) * (bands.length - 1)))
    var bVal = bands[bandIndex] || 0.0
    var ringAudioPulse = 1.0 + (bVal * 0.25) + (beatDrop * 0.20)

    var rx = (width * 0.42) * scale * ringAudioPulse
    var ry = (height * 0.42) * scale * ringAudioPulse
    var ringRot = rotBase + (1.0 - z) * 0.3

    var alpha = Math.min(1.0, scale * 1.4) * (0.35 + bVal * 0.45 + beatDrop * 0.20)

    canvas.strokeStyle = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, (1.0 - z) * 0.25 + highs * 0.20, alpha.toFixed(2))
    canvas.lineWidth = Math.max(1.0, scale * 2.0)

    canvas.beginPath()
    for (var s = 0; s <= numSides; s++) {
      var a = ringRot + (s * (Math.PI * 2 / numSides))
      var px = cx + Math.cos(a) * rx
      var py = cy + Math.sin(a) * ry
      if (s === 0) canvas.moveTo(px, py)
      else canvas.lineTo(px, py)
    }
    canvas.stroke()
  }

  var coreR = Math.max(2.5, (height * 0.06) * (1.0 + bass * 0.6 + beatDrop * 0.4))
  var coreGrad = canvas.createRadialGradient(cx, cy, 0, cx, cy, coreR * 2.0)
  coreGrad.addColorStop(0, VisualizerHelpers.rgba(frameData.foreground, (0.80 + beatDrop * 0.2).toFixed(2)))
  coreGrad.addColorStop(0.4, VisualizerHelpers.rgba(frameData.accent, 0.5))
  coreGrad.addColorStop(1, VisualizerHelpers.rgba(frameData.accent, 0))

  canvas.fillStyle = coreGrad
  canvas.beginPath()
  canvas.arc(cx, cy, coreR * 2.0, 0, Math.PI * 2)
  canvas.fill()
}

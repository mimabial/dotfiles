.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var stereo = frameData.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var width = frameData.width, height = frameData.height, animationState = frameData.state, palette = frameData.colors || []
  var pad = 14
  var trackX = pad, trackW = Math.max(1, width - pad * 2)
  var trackY = Math.round(height * 0.36), trackH = Math.max(6, Math.round(height * 0.34))
  var mid = trackX + trackW / 2

  function posFor(value) { return trackX + trackW * (value + 1) / 2 }

  var n = Math.min(left.length, right.length)
  var sumLR = 0, sumLL = 0, sumRR = 0
  for (var i = 0; i < n; i++) {
    var lv = Number(left[i]) || 0, rv = Number(right[i]) || 0
    sumLR += lv * rv; sumLL += lv * lv; sumRR += rv * rv
  }
  var denom = Math.sqrt(sumLL * sumRR)
  var target = (frameData.playing && denom > 1e-9) ? Math.max(-1, Math.min(1, sumLR / denom)) : 0

  var now = Date.now()
  if (animationState.corrValue === undefined) { animationState.corrValue = 0; animationState.corrHold = 0; animationState.corrLast = now }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.corrLast) / 1000))
  animationState.corrLast = now
  animationState.corrValue += (target - animationState.corrValue) * (1 - Math.exp(-elapsedSeconds / 0.30))
  animationState.corrHold = Math.min(animationState.corrValue, animationState.corrHold + 0.35 * elapsedSeconds)

  var value = animationState.corrValue
  var danger = palette[1] || frameData.accent

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.07)
  canvas.fillRect(trackX, trackY, trackW, trackH)

  var ticks = [-1, -0.5, 0, 0.5, 1]
  canvas.lineWidth = 1
  for (var t = 0; t < ticks.length; t++) {
    var tx = Math.round(posFor(ticks[t])) + 0.5
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, ticks[t] === 0 ? 0.30 : 0.12)
    canvas.beginPath(); canvas.moveTo(tx, trackY); canvas.lineTo(tx, trackY + trackH); canvas.stroke()
  }

  var valueX = posFor(value)
  var fillW = Math.abs(valueX - mid)
  if (fillW >= 1) {
    var tint = value < 0 ? danger : frameData.accent
    var gradient = canvas.createLinearGradient(mid, 0, valueX, 0)
    gradient.addColorStop(0, VisualizerHelpers.rgba(tint, 0.25))
    gradient.addColorStop(1, VisualizerHelpers.rgba(tint, 0.85))
    canvas.fillStyle = gradient
    canvas.fillRect(Math.min(mid, valueX), trackY, fillW, trackH)
  }

  canvas.fillStyle = VisualizerHelpers.rgba(animationState.corrHold < 0 ? danger : frameData.dim, 0.9)
  canvas.fillRect(Math.round(posFor(animationState.corrHold)), trackY - 2, 1, trackH + 4)

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.95)
  canvas.fillRect(Math.round(valueX) - 1, trackY - 2, 2, trackH + 4)

  canvas.font = "7px monospace"
  canvas.fillStyle = VisualizerHelpers.rgba(frameData.dim, 0.9)
  canvas.textAlign = "left"; canvas.fillText("OUT OF PHASE", trackX, trackY - 5)
  canvas.textAlign = "right"; canvas.fillText("MONO", trackX + trackW, trackY - 5)
  canvas.textAlign = "center"
  canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.95)
  canvas.fillText((value >= 0 ? "+" : "") + value.toFixed(2), mid, trackY - 5)

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.dim, 0.8)
  canvas.fillText("-1", posFor(-1), height - 1)
  canvas.fillText("0", mid, height - 1)
  canvas.fillText("+1", posFor(1), height - 1)
}

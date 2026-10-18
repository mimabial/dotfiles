.pragma library
.import "helpers.js" as VisualizerHelpers

function trace(canvas, samples, width, center, scale, color) {
  if (!samples || samples.length < 2) return
  canvas.strokeStyle = color
  canvas.lineWidth = 1.35
  canvas.beginPath()
  for (var i = 0; i < samples.length; i++) {
    var x = i * width / (samples.length - 1)
    var y = Math.max(center - scale, Math.min(center + scale, center - Number(samples[i] || 0) * scale))
    if (i === 0) canvas.moveTo(x, y)
    else canvas.lineTo(x, y)
  }
  canvas.stroke()
}

function render(canvas, frameData) {
  var stereo = frameData.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var width = frameData.width, height = frameData.height, top = height * 0.25, bottom = height * 0.75, scale = height * 0.21
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, 0.12); canvas.lineWidth = 1
  canvas.beginPath(); canvas.moveTo(0, top); canvas.lineTo(width, top); canvas.moveTo(0, bottom); canvas.lineTo(width, bottom); canvas.stroke()
  if (frameData.playing && left.length > 1 && right.length > 1) {
    trace(canvas, left, width, top, scale, VisualizerHelpers.rgba(frameData.accent, 0.95))
    trace(canvas, right, width, bottom, scale, VisualizerHelpers.rgba(frameData.foreground, 0.85))
  }
  canvas.fillStyle = VisualizerHelpers.rgba(frameData.dim, 0.9); canvas.font = "7px monospace"; canvas.textAlign = "left"
  canvas.fillText("L", 2, top - 2); canvas.fillText("R", 2, bottom - 2)
}

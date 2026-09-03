// Wave — triggered, amplitude-linear stereo oscilloscope.
.pragma library
.import "helpers.js" as H

function trace(ctx, samples, width, center, scale, color) {
  if (!samples || samples.length < 2) return
  ctx.strokeStyle = color
  ctx.lineWidth = 1.35
  ctx.beginPath()
  for (var i = 0; i < samples.length; i++) {
    var x = i * width / (samples.length - 1)
    var y = Math.max(center - scale, Math.min(center + scale, center - Number(samples[i] || 0) * scale))
    if (i === 0) ctx.moveTo(x, y)
    else ctx.lineTo(x, y)
  }
  ctx.stroke()
}

function render(ctx, d) {
  var stereo = d.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var w = d.width, h = d.height, top = h * 0.25, bottom = h * 0.75, scale = h * 0.21
  ctx.strokeStyle = H.rgba(d.foreground, 0.12); ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(0, top); ctx.lineTo(w, top); ctx.moveTo(0, bottom); ctx.lineTo(w, bottom); ctx.stroke()
  if (d.playing && left.length > 1 && right.length > 1) {
    trace(ctx, left, w, top, scale, H.rgba(d.accent, 0.95))
    trace(ctx, right, w, bottom, scale, H.rgba(d.foreground, 0.85))
  }
  ctx.fillStyle = H.rgba(d.dim, 0.9); ctx.font = "7px monospace"; ctx.textAlign = "left"
  ctx.fillText("L", 2, top - 2); ctx.fillText("R", 2, bottom - 2)
}

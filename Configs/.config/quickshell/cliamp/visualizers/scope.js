// Scope — true L/R vectorscope: left drives X and right drives Y.
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var stereo = d.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var w = d.width, h = d.height, cx = w / 2, cy = h / 2
  var scaleX = Math.max(1, w / 2 - 3), scaleY = Math.max(1, h / 2 - 3)
  ctx.strokeStyle = H.rgba(d.foreground, 0.12); ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(cx, 1); ctx.lineTo(cx, h - 1); ctx.moveTo(1, cy); ctx.lineTo(w - 1, cy); ctx.stroke()
  ctx.strokeStyle = H.rgba(d.accent, 0.92); ctx.lineWidth = 1.25; ctx.beginPath()
  if (d.playing && left.length > 1 && right.length === left.length) {
    for (var i = 0; i < left.length; i++) {
      var x = Math.max(2, Math.min(w - 3, cx + Number(left[i] || 0) * scaleX))
      var y = Math.max(2, Math.min(h - 3, cy - Number(right[i] || 0) * scaleY))
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    }
  } else {
    ctx.moveTo(cx - 1, cy); ctx.lineTo(cx + 1, cy)
  }
  ctx.stroke()
  ctx.fillStyle = H.rgba(d.dim, 0.8); ctx.font = "7px monospace"; ctx.textAlign = "left"
  ctx.fillText("L", w - 8, cy - 2); ctx.fillText("R", cx + 3, 8)
}

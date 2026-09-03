// Stereo — calibrated channel RMS, sample-peak and 4× true-peak meters.
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var stereo = d.stereo || {}, levels = stereo.levels || [0, 0]
  var truePeaks = stereo.peaks || [0, 0], samplePeaks = stereo.sample_peaks || truePeaks
  var rmsDb = stereo.rms_dbfs || [-72, -72], trueDb = stereo.true_peak_dbfs || [-72, -72]
  var w = d.width, h = d.height, left = 14, right = 42, meterW = Math.max(1, w - left - right)
  var laneH = h / 2 - 3, ticks = [-60, -48, -36, -24, -12, -6, 0]

  ctx.font = "7px monospace"
  ctx.textAlign = "center"
  for (var t = 0; t < ticks.length; t++) {
    var tx = left + meterW * ((ticks[t] + 72) / 72)
    ctx.strokeStyle = H.rgba(d.foreground, ticks[t] === 0 ? 0.25 : 0.10)
    ctx.beginPath(); ctx.moveTo(tx, 1); ctx.lineTo(tx, h - 1); ctx.stroke()
  }

  for (var channel = 0; channel < 2; channel++) {
    var y = channel ? h / 2 + 2 : 1
    var level = d.playing ? Math.max(0, Math.min(1, levels[channel] || 0)) : 0
    var peak = d.playing ? Math.max(0, Math.min(1, truePeaks[channel] || 0)) : 0
    var sample = d.playing ? Math.max(0, Math.min(1, samplePeaks[channel] || 0)) : 0
    ctx.fillStyle = H.rgba(d.foreground, 0.07)
    ctx.fillRect(left, y, meterW, laneH)
    var gradient = ctx.createLinearGradient(left, 0, left + meterW, 0)
    gradient.addColorStop(0, H.rgba(d.dim, 0.8))
    gradient.addColorStop(0.75, H.rgba(d.accent, 0.95))
    gradient.addColorStop(1, H.rgba(d.foreground, 1))
    ctx.fillStyle = gradient
    ctx.fillRect(left, y, meterW * level, laneH)
    if (sample > 0) { ctx.fillStyle = H.rgba(d.accent, 0.65); ctx.fillRect(left + meterW * sample - 1, y, 1, laneH) }
    if (peak > 0) { ctx.fillStyle = H.rgba(d.foreground, 1); ctx.fillRect(left + meterW * peak - 1, y, 2, laneH) }
    ctx.textAlign = "left"; ctx.fillStyle = H.rgba(d.dim, 1)
    ctx.fillText(channel ? "R" : "L", 2, y + laneH - 2)
    var rmsValue = Number(rmsDb[channel]), peakValue = Number(trueDb[channel])
    if (!Number.isFinite(rmsValue)) rmsValue = -72
    if (!Number.isFinite(peakValue)) peakValue = -72
    ctx.textAlign = "right"; ctx.fillStyle = H.rgba(d.foreground, 0.9)
    ctx.fillText(rmsValue.toFixed(1), w - 2, y + laneH - 2)
    if (peakValue >= -0.1) {
      ctx.fillStyle = H.rgba(d.foreground, 1)
      ctx.fillRect(w - 3, y, 3, laneH)
    }
  }
}

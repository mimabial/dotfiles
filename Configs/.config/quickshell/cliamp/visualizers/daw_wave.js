// DAW Meter — calibrated RMS body with sample-peak and 4× true-peak markers.
.pragma library
.import "helpers.js" as H

function render(ctx, d) {
  var stereo = d.stereo || {}, levels = stereo.levels || [0, 0]
  var samplePeaks = stereo.sample_peaks || [0, 0], truePeaks = stereo.peaks || [0, 0]
  var rmsDb = stereo.rms_dbfs || [-72, -72], trueDb = stereo.true_peak_dbfs || [-72, -72]
  var w = d.width, h = d.height, left = 20, right = 47, meterW = Math.max(1, w - left - right)
  var ticks = [-60, -48, -36, -24, -18, -12, -6, 0], laneH = Math.max(5, h / 2 - 8)
  ctx.font = "7px monospace"; ctx.textAlign = "center"
  for (var t = 0; t < ticks.length; t++) {
    var tx = left + meterW * ((ticks[t] + 72) / 72)
    ctx.strokeStyle = H.rgba(d.foreground, 0.12)
    ctx.beginPath(); ctx.moveTo(tx, 9); ctx.lineTo(tx, h); ctx.stroke()
    if (ticks[t] === -48 || ticks[t] === -24 || ticks[t] === -12 || ticks[t] === 0) {
      ctx.fillStyle = H.rgba(d.dim, 0.8); ctx.fillText(String(ticks[t]), tx, 7)
    }
  }
  for (var channel = 0; channel < 2; channel++) {
    var y = 10 + channel * (laneH + 3)
    var level = d.playing ? Math.max(0, Math.min(1, Number(levels[channel] || 0))) : 0
    var sample = d.playing ? Math.max(0, Math.min(1, Number(samplePeaks[channel] || 0))) : 0
    var peak = d.playing ? Math.max(0, Math.min(1, Number(truePeaks[channel] || 0))) : 0
    var meter = ctx.createLinearGradient(left, 0, left + meterW, 0)
    meter.addColorStop(0, H.rgba(d.dim, 0.75)); meter.addColorStop(0.75, H.rgba(d.accent, 0.95)); meter.addColorStop(1, H.rgba(d.foreground, 1))
    ctx.fillStyle = H.rgba(d.foreground, 0.07); ctx.fillRect(left, y, meterW, laneH)
    ctx.fillStyle = meter; ctx.fillRect(left, y, meterW * level, laneH)
    if (sample > 0) { ctx.fillStyle = H.rgba(d.accent, 0.7); ctx.fillRect(left + meterW * sample - 1, y, 1, laneH) }
    if (peak > 0) { ctx.fillStyle = H.rgba(d.foreground, 1); ctx.fillRect(left + meterW * peak - 1, y, 2, laneH) }
    ctx.fillStyle = H.rgba(d.foreground, 0.9); ctx.textAlign = "left"; ctx.fillText(channel ? "R" : "L", 3, y + laneH - 1)
    var rmsValue = Number(rmsDb[channel]), peakValue = Number(trueDb[channel])
    if (!Number.isFinite(rmsValue)) rmsValue = -72
    if (!Number.isFinite(peakValue)) peakValue = -72
    ctx.textAlign = "right"; ctx.fillText(rmsValue.toFixed(1), w - 2, y + laneH - 1)
    if (peakValue >= -0.1) { ctx.fillStyle = H.rgba(d.foreground, 1); ctx.fillRect(w - 3, y, 3, laneH) }
  }
}

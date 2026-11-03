.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var stereo = frameData.stereo || {}, levels = stereo.levels || [0, 0]
  var samplePeaks = stereo.sample_peaks || [0, 0], truePeaks = stereo.peaks || [0, 0]
  var rmsDb = stereo.rms_dbfs || [-72, -72], trueDb = stereo.true_peak_dbfs || [-72, -72]
  var width = frameData.width, height = frameData.height, left = 20, right = 47, meterW = Math.max(1, width - left - right)
  var ticks = [-60, -48, -36, -24, -18, -12, -6, 0], laneH = Math.max(5, height / 2 - 8)
  canvas.font = "7px monospace"; canvas.textAlign = "center"
  for (var t = 0; t < ticks.length; t++) {
    var tx = left + meterW * ((ticks[t] + 72) / 72)
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, 0.12)
    canvas.beginPath(); canvas.moveTo(tx, 9); canvas.lineTo(tx, height); canvas.stroke()
    if (ticks[t] === -48 || ticks[t] === -24 || ticks[t] === -12 || ticks[t] === 0) {
      canvas.fillStyle = VisualizerHelpers.rgba(frameData.dim, 0.8); canvas.fillText(String(ticks[t]), tx, 7)
    }
  }
  for (var channel = 0; channel < 2; channel++) {
    var y = 10 + channel * (laneH + 3)
    var level = frameData.playing ? Math.max(0, Math.min(1, Number(levels[channel] || 0))) : 0
    var sample = frameData.playing ? Math.max(0, Math.min(1, Number(samplePeaks[channel] || 0))) : 0
    var peak = frameData.playing ? Math.max(0, Math.min(1, Number(truePeaks[channel] || 0))) : 0
    var meter = canvas.createLinearGradient(left, 0, left + meterW, 0)
    meter.addColorStop(0, VisualizerHelpers.rgba(frameData.dim, 0.75)); meter.addColorStop(0.75, VisualizerHelpers.rgba(frameData.accent, 0.95)); meter.addColorStop(1, VisualizerHelpers.rgba(frameData.foreground, 1))
    canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.07); canvas.fillRect(left, y, meterW, laneH)
    canvas.fillStyle = meter; canvas.fillRect(left, y, meterW * level, laneH)
    if (sample > 0) { canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, 0.7); canvas.fillRect(left + meterW * sample - 1, y, 1, laneH) }
    if (peak > 0) { canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 1); canvas.fillRect(left + meterW * peak - 1, y, 2, laneH) }
    canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.9); canvas.textAlign = "left"; canvas.fillText(channel ? "R" : "L", 3, y + laneH - 1)
    var rmsValue = Number(rmsDb[channel]), peakValue = Number(trueDb[channel])
    if (!Number.isFinite(rmsValue)) rmsValue = -72
    if (!Number.isFinite(peakValue)) peakValue = -72
    canvas.textAlign = "right"; canvas.fillText(rmsValue.toFixed(1), width - 2, y + laneH - 1)
    if (peakValue >= -0.1) { canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 1); canvas.fillRect(width - 3, y, 3, laneH) }
  }
}

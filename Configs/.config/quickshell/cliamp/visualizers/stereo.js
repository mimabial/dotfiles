.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var stereo = frameData.stereo || {}, levels = stereo.levels || [0, 0]
  var truePeaks = stereo.peaks || [0, 0], samplePeaks = stereo.sample_peaks || truePeaks
  var rmsDb = stereo.rms_dbfs || [-72, -72], trueDb = stereo.true_peak_dbfs || [-72, -72]
  var width = frameData.width, height = frameData.height, left = 14, right = 42, meterW = Math.max(1, width - left - right)
  var laneH = height / 2 - 3, ticks = [-60, -48, -36, -24, -12, -6, 0]

  canvas.font = "7px monospace"
  canvas.textAlign = "center"
  for (var t = 0; t < ticks.length; t++) {
    var tx = left + meterW * ((ticks[t] + 72) / 72)
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, ticks[t] === 0 ? 0.25 : 0.10)
    canvas.beginPath(); canvas.moveTo(tx, 1); canvas.lineTo(tx, height - 1); canvas.stroke()
  }

  for (var channel = 0; channel < 2; channel++) {
    var y = channel ? height / 2 + 2 : 1
    var level = frameData.playing ? Math.max(0, Math.min(1, levels[channel] || 0)) : 0
    var peak = frameData.playing ? Math.max(0, Math.min(1, truePeaks[channel] || 0)) : 0
    var sample = frameData.playing ? Math.max(0, Math.min(1, samplePeaks[channel] || 0)) : 0
    canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.07)
    canvas.fillRect(left, y, meterW, laneH)
    var gradient = canvas.createLinearGradient(left, 0, left + meterW, 0)
    gradient.addColorStop(0, VisualizerHelpers.rgba(frameData.dim, 0.8))
    gradient.addColorStop(0.75, VisualizerHelpers.rgba(frameData.accent, 0.95))
    gradient.addColorStop(1, VisualizerHelpers.rgba(frameData.foreground, 1))
    canvas.fillStyle = gradient
    canvas.fillRect(left, y, meterW * level, laneH)
    if (sample > 0) { canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, 0.65); canvas.fillRect(left + meterW * sample - 1, y, 1, laneH) }
    if (peak > 0) { canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 1); canvas.fillRect(left + meterW * peak - 1, y, 2, laneH) }
    canvas.textAlign = "left"; canvas.fillStyle = VisualizerHelpers.rgba(frameData.dim, 1)
    canvas.fillText(channel ? "R" : "L", 2, y + laneH - 2)
    var rmsValue = Number(rmsDb[channel]), peakValue = Number(trueDb[channel])
    if (!Number.isFinite(rmsValue)) rmsValue = -72
    if (!Number.isFinite(peakValue)) peakValue = -72
    canvas.textAlign = "right"; canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 0.9)
    canvas.fillText(rmsValue.toFixed(1), width - 2, y + laneH - 2)
    if (peakValue >= -0.1) {
      canvas.fillStyle = VisualizerHelpers.rgba(frameData.foreground, 1)
      canvas.fillRect(width - 3, y, 3, laneH)
    }
  }
}

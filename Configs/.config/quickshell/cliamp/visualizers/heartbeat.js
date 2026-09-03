// Heartbeat — beat-triggered P–QRS–T ECG sweep.
.pragma library
.import "helpers.js" as H

function gaussian(value, center, width) {
  var distance = (value - center) / width
  return Math.exp(-0.5 * distance * distance)
}

function cardiacShape(age) {
  if (age < 0 || age > 0.46) return 0
  return 0.13 * gaussian(age, 0.065, 0.022)
    - 0.18 * gaussian(age, 0.145, 0.009)
    + 1.00 * gaussian(age, 0.165, 0.008)
    - 0.32 * gaussian(age, 0.190, 0.012)
    + 0.24 * gaussian(age, 0.315, 0.045)
}

function render(ctx, d) {
  var w = Math.max(2, Math.floor(d.width)), h = d.height, midY = h / 2
  var s = d.state, now = Date.now(), playing = d.playing
  if (!s.ecgBuffer || s.ecgBuffer.length !== w || s.ecgHeight !== h) {
    s.ecgBuffer = new Array(w).fill(midY)
    s.ecgHeight = h
    s.ecgHead = 0
    s.ecgPixelCarry = 0
    s.ecgPulseAge = -1
    s.ecgPulseStrength = 0
    s.ecgPrevBass = 0
    s.ecgFluxFloor = 0
    s.ecgPrevBeat = 0
    s.ecgLastOnset = 0
    s.ecgBeatPeriod = 0
    s.ecgLastTime = now
  }

  var dt = Math.min(0.12, Math.max(0.001, (now - s.ecgLastTime) / 1000))
  s.ecgLastTime = now
  var bands = d.rawBands && d.rawBands.length ? d.rawBands : (d.bands || [])
  var bass = H.bandAvg(bands, 0, Math.min(5, bands.length))
  var flux = Math.max(0, bass - s.ecgPrevBass)
  s.ecgPrevBass = bass
  s.ecgFluxFloor += (flux - s.ecgFluxFloor) * (1 - Math.exp(-dt / 1.2))

  var beat = d.beatDrop || 0
  var sharedOnset = beat > 0.72 && s.ecgPrevBeat <= 0.72
  var localOnset = flux > Math.max(0.045, s.ecgFluxFloor * 2.4) && bass > 0.22
  var onsetInterval = now - s.ecgLastOnset
  var minimumInterval = s.ecgBeatPeriod > 0 ? Math.max(280, s.ecgBeatPeriod * 0.62) : 320
  var canTrigger = onsetInterval > minimumInterval
  var triggered = false
  if (playing && canTrigger && (sharedOnset || localOnset)) {
    s.ecgPulseStrength = Math.min(1, 0.62 + bass * 0.38 + beat * 0.15)
    if (s.ecgLastOnset > 0 && onsetInterval >= 300 && onsetInterval <= 1200) {
      if (s.ecgBeatPeriod <= 0) s.ecgBeatPeriod = onsetInterval
      else if (onsetInterval > s.ecgBeatPeriod * 0.72 && onsetInterval < s.ecgBeatPeriod * 1.35)
        s.ecgBeatPeriod += (onsetInterval - s.ecgBeatPeriod) * 0.18
    }
    s.ecgLastOnset = now
    triggered = true
  }
  s.ecgPrevBeat = beat

  // About 3.4 seconds per sweep, independent of repaint rate.
  var pixelsPerSecond = w / 3.4
  var sampleDt = 1 / pixelsPerSecond
  if (triggered) {
    // The musical onset is the R peak. Fill P and Q into the already-scanned
    // segment so the complete ECG form is visible without adding perceptible lag.
    var rAge = 0.165
    var historyPixels = Math.ceil(rAge / sampleDt)
    for (var back = historyPixels; back > 0; back--) {
      var historyAge = Math.max(0, rAge - back * sampleDt)
      var historyIndex = (s.ecgHead - back + w) % w
      var historyValue = cardiacShape(historyAge) * s.ecgPulseStrength
      s.ecgBuffer[historyIndex] = Math.max(2, Math.min(h - 3, midY - historyValue * h * 0.43))
    }
    var rValue = cardiacShape(rAge) * s.ecgPulseStrength
    s.ecgBuffer[s.ecgHead] = Math.max(2, Math.min(h - 3, midY - rValue * h * 0.43))
    s.ecgHead = (s.ecgHead + 1) % w
    s.ecgPulseAge = rAge + sampleDt
  }
  s.ecgPixelCarry += pixelsPerSecond * dt
  var steps = Math.min(16, Math.floor(s.ecgPixelCarry))
  s.ecgPixelCarry -= steps
  for (var step = 0; step < steps; step++) {
    var value = playing && s.ecgPulseAge >= 0 ? cardiacShape(s.ecgPulseAge) * s.ecgPulseStrength : 0
    var y = Math.max(2, Math.min(h - 3, midY - value * h * 0.43))
    s.ecgBuffer[s.ecgHead] = y
    s.ecgHead = (s.ecgHead + 1) % w
    if (s.ecgPulseAge >= 0) {
      s.ecgPulseAge += sampleDt
      if (s.ecgPulseAge > 0.46) s.ecgPulseAge = -1
    }
  }

  ctx.strokeStyle = H.rgba(d.accent, 0.10)
  ctx.lineWidth = 1
  ctx.beginPath()
  for (var gx = 0; gx < w; gx += 12) { ctx.moveTo(gx, 0); ctx.lineTo(gx, h) }
  for (var gy = 4; gy < h; gy += 12) { ctx.moveTo(0, gy); ctx.lineTo(w, gy) }
  ctx.stroke()
  ctx.strokeStyle = H.rgba(d.accent, 0.22)
  ctx.beginPath(); ctx.moveTo(0, midY); ctx.lineTo(w, midY); ctx.stroke()

  var gap = 10
  function inGap(x) { return (x - s.ecgHead + w) % w < gap }
  function trace(width, color) {
    ctx.lineWidth = width
    ctx.strokeStyle = color
    ctx.beginPath()
    for (var x = 1; x < w; x++) {
      if (inGap(x - 1) || inGap(x)) continue
      ctx.moveTo(x - 1, s.ecgBuffer[x - 1])
      ctx.lineTo(x, s.ecgBuffer[x])
    }
    ctx.stroke()
  }
  trace(4, H.rgba(d.accent, 0.16))
  trace(1.5, H.rgba(d.accent, 0.95))

  var cursor = (s.ecgHead - 1 + w) % w
  ctx.fillStyle = H.rgba(d.foreground, 0.95)
  ctx.beginPath(); ctx.arc(cursor, s.ecgBuffer[cursor], 2, 0, Math.PI * 2); ctx.fill()
}

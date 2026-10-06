// CRT Linear Radar Scope — stereo-positioned audio transients scanned across a range grid.
.pragma library
.import "helpers.js" as H

// Range axis: near edge and span, shared by addEcho and the graduation labels so the
// two can never disagree about what a given row means.
var RANGE_NEAR = 0.05
var RANGE_SPAN = 0.90
var MAX_ECHOES = 6
var ECHO_PULSE_SECONDS = 0.55
var ECHO_IDLE_GLOW = 0.06
var WAVE_BEATS = 4

// Geometric interpolation into band_edges_hz, which spectrum.py builds with geomspace.
function bandHz(edges, bandIndex) {
  if (!edges || edges.length < 2) return 0
  var i = Math.max(0, Math.min(edges.length - 2, Math.floor(bandIndex)))
  var frac = Math.max(0, Math.min(1, bandIndex - i))
  var lo = Number(edges[i]) || 0, hi = Number(edges[i + 1]) || 0
  if (lo <= 0 || hi <= 0) return 0
  return lo * Math.pow(hi / lo, frac)
}

function hzLabel(hz) {
  if (hz <= 0) return ""
  if (hz >= 10000) return Math.round(hz / 1000) + "k"
  if (hz >= 1000) return (hz / 1000).toFixed(1) + "k"
  return String(Math.round(hz))
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, Number(value || 0)))
}

function stereoBearing(stereo, band, dbFloor) {
  var left = stereo && stereo.left ? stereo.left : []
  var right = stereo && stereo.right ? stereo.right : []
  if (left[band] === undefined || right[band] === undefined) return 0.5
  var floor = Number(dbFloor)
  if (!isFinite(floor) || floor >= 0) floor = -72
  var leftAmplitude = Math.pow(10, (floor + clamp(left[band], 0, 1) * -floor) / 20)
  var rightAmplitude = Math.pow(10, (floor + clamp(right[band], 0, 1) * -floor) / 20)
  return clamp(rightAmplitude / (leftAmplitude + rightAmplitude), 0.02, 0.98)
}

function addEcho(s, band, bandCount, strength, stereo, dbFloor, outerRange) {
  var frequency = bandCount > 1 ? band / (bandCount - 1) : 0.5
  var pan = stereoBearing(stereo, band, dbFloor)
  var distributed = (s.crtSequence * 0.61803398875 + frequency * 0.29) % 1
  var bearing = clamp(distributed * 0.88 + pan * 0.12, 0.02, 0.98)
  s.crtSequence++
  var range = (RANGE_NEAR + frequency * RANGE_SPAN) * outerRange
  for (var index = 0; index < s.crtEchoes.length; index++) {
    var existing = s.crtEchoes[index]
    if (Math.abs(existing.bearing - bearing) < 0.04 && Math.abs(existing.range - range) < 0.07) {
      if (existing.pulseProgress < 0) existing.strength = Math.max(existing.strength, clamp(strength, 0.25, 1))
      existing.lit = Math.max(existing.lit, 0.08)
      return
    }
  }
  if (s.crtEchoes.length >= MAX_ECHOES) return
  var echo = {
    bearing: bearing,
    range: range,
    azimuth: bearing * 2,
    depth: 0.5 - Math.sin(bearing * Math.PI * 2) * range / 2,
    strength: clamp(strength, 0.25, 1),
    lit: ECHO_IDLE_GLOW,
    pulseProgress: -1
  }
  s.crtEchoes.push(echo)
}

function render(ctx, d) {
  var w = d.width, h = d.height
  var unit = d.S, rangeSteps = 4, bearingSteps = rangeSteps * 3, perspectiveDepth = 1.8
  var scopeLeft = unit * 2, scopeRight = w - scopeLeft, scopeTop = unit * 1.5, scopeBottom = h - scopeLeft
  var scopeWidth = scopeRight - scopeLeft, scopeHeight = scopeBottom - scopeTop
  var scopeElevation = scopeHeight / 2
  function project(azimuth, range, elevation) {
    var angle = azimuth * Math.PI, radius = range / 2
    var scale = 1 / (1 + (0.5 - Math.sin(angle) * radius) * perspectiveDepth)
    return { x: w / 2 + Math.cos(angle) * radius * scopeWidth * scale,
      y: scopeTop + (scopeHeight - elevation) * scale, scale: scale }
  }
  var center = project(0, 0, 0), rim = []
  var bands = d.rawBands && d.rawBands.length ? d.rawBands : (d.bands || [])
  var s = d.state, now = Date.now()
  if (s.crtLinear !== true) {
    s.crtLinear = true
    s.crtLastTime = now; s.crtSweep = 0
    s.crtSweepSpeed = 0.46; s.crtBeatPeriod = 0; s.crtLastBeatTime = 0
    s.crtEchoes = []; s.crtWaveProgress = 1; s.crtWaveSpeed = s.crtSweepSpeed
    s.crtPrevBands = []; s.crtSpawnClock = 0; s.crtFluxFloor = 0
    s.crtPrevBeat = 0; s.crtSequence = 0
  }
  var dt = Math.min(0.12, Math.max(0.001, (now - s.crtLastTime) / 1000))
  s.crtLastTime = now; s.crtSpawnClock += dt

  var beat = clamp(d.beatDrop, 0, 1)
  var beatEdge = beat > 0.72 && s.crtPrevBeat <= 0.72
  s.crtPrevBeat = beat
  if (d.playing && beatEdge) {
    if (s.crtLastBeatTime > 0) {
      var beatInterval = now - s.crtLastBeatTime
      if (beatInterval >= 280 && beatInterval <= 1200) {
        if (s.crtBeatPeriod <= 0) s.crtBeatPeriod = beatInterval
        else if (beatInterval > s.crtBeatPeriod * 0.65 && beatInterval < s.crtBeatPeriod * 1.45)
          s.crtBeatPeriod += (beatInterval - s.crtBeatPeriod) * 0.22
      }
    }
    s.crtLastBeatTime = now
  }
  var beatLockFresh = s.crtBeatPeriod > 0
    && now - s.crtLastBeatTime < Math.max(3500, s.crtBeatPeriod * 6)
  var targetSweepSpeed = beatLockFresh
    ? clamp(1 / (s.crtBeatPeriod / 1000 * 4), 0.21, 0.76) : 0.46
  s.crtSweepSpeed += (targetSweepSpeed - s.crtSweepSpeed) * (1 - Math.exp(-dt / 0.85))

  s.crtSweep = (s.crtSweep + dt * s.crtSweepSpeed) % 2

  // One strong onset creates a target; bass is near, treble is far.
  var bestBand = -1, bestScore = 0, bestRise = 0, bestLevel = 0
  var bandScores = [], bandRises = [], bandLevels = []
  for (var band = 0; band < bands.length; band++) {
    var level = clamp(bands[band], 0, 1)
    var previous = Number(s.crtPrevBands[band] || 0)
    var rise = Math.max(0, level - previous)
    var score = rise * 3.2 + level * 0.18
    bandScores[band] = score; bandRises[band] = rise; bandLevels[band] = level
    if (score > bestScore) {
      bestBand = band; bestScore = score; bestRise = rise; bestLevel = level
    }
    s.crtPrevBands[band] = level
  }
  var secondBand = -1, secondScore = 0
  for (var candidate = 0; candidate < bands.length; candidate++) {
    if (Math.abs(candidate - bestBand) >= 3 && bandScores[candidate] > secondScore) {
      secondBand = candidate; secondScore = bandScores[candidate]
    }
  }
  var onsetThreshold = Math.max(0.065, s.crtFluxFloor * 2.4)
  var localOnset = bestRise > onsetThreshold && bestLevel > 0.22
  s.crtFluxFloor += (bestRise - s.crtFluxFloor) * (1 - Math.exp(-dt / 1.4))

  ctx.fillStyle = H.rgba(d.surface, 0.32)
  for (var scanY = 0; scanY < h; scanY += 2) ctx.fillRect(0, scanY, w, 1)
  ctx.lineWidth = 1

  // Range rings: the axis a target's position is exact in, so they carry the weight.
  var planeDepth = 1 + perspectiveDepth / 2
  function ringPath(radius) {
    var radialDepth = radius * perspectiveDepth / 2
    var ellipseDepth = planeDepth * planeDepth - radialDepth * radialDepth
    ctx.save(); ctx.translate(w / 2, scopeTop + scopeHeight * planeDepth / ellipseDepth)
    ctx.scale(scopeWidth * radius / (2 * Math.sqrt(ellipseDepth)), scopeHeight * radialDepth / ellipseDepth)
    ctx.moveTo(1, 0); ctx.arc(0, 0, 1, 0, Math.PI * 2); ctx.restore()
  }
  ctx.strokeStyle = H.rgba(d.accent, 0.26)
  ctx.beginPath()
  var outerSteps = Math.ceil(2 * planeDepth * rangeSteps / perspectiveDepth) - 1
  for (var row = 1; row <= outerSteps; row++) ringPath(row / rangeSteps)
  ctx.stroke()
  var outerRange = outerSteps / rangeSteps, waveStart = s.crtWaveProgress
  if (d.playing && (beatEdge || localOnset) && s.crtWaveProgress >= 1) {
    s.crtWaveProgress = 0; waveStart = 0
    s.crtWaveSpeed = beatLockFresh ? 1000 / (s.crtBeatPeriod * WAVE_BEATS) : s.crtSweepSpeed
  }
  s.crtWaveProgress = Math.min(1, s.crtWaveProgress + dt * s.crtWaveSpeed)
  var waveRange = s.crtWaveProgress * outerRange, waveTravel = (s.crtWaveProgress - waveStart) * outerRange
  ctx.strokeStyle = H.rgba(d.accent, Math.min(1, (outerRange - waveRange) * rangeSteps) * 0.56)
  ctx.lineWidth = unit
  ctx.beginPath(); if (s.crtWaveProgress < 1) ringPath(waveRange); ctx.stroke()
  ctx.lineWidth = 1

  // Bearing lines: dots on a quarter duty cycle, so they stay lighter than the rings
  // even though each dot is crisper than an antialiased stroke.
  ctx.fillStyle = H.rgba(d.accent, 0.20)
  for (var column = 0; column < bearingSteps; column++) {
    var edge = project(column * 2 / bearingSteps, outerRange, 0)
    rim.push(edge)
    var dx = edge.x - center.x, dy = edge.y - center.y
    var dotSteps = Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / (unit * 2))
    var visibleSteps = dotSteps * Math.min(1,
      dx === 0 ? 1 : (dx > 0 ? w - 1 - center.x : -center.x) / dx,
      dy === 0 ? 1 : (dy > 0 ? h - 1 - center.y : -center.y) / dy)
    for (var dot = 1; dot < visibleSteps; dot++)
      ctx.fillRect(Math.round(center.x + dx * dot / dotSteps), Math.round(center.y + dy * dot / dotSteps), 1, 1)
  }

  ctx.strokeStyle = H.rgba(d.accent, 0.38)
  ctx.beginPath()
  for (var tick = 0; tick < bearingSteps; tick++) {
    var tickPoint = project(tick * 2 / bearingSteps, outerRange - (tick % (bearingSteps / 4) === 0 ? unit * 2 : unit) / scopeHeight, 0)
    ctx.moveTo(rim[tick].x, rim[tick].y); ctx.lineTo(tickPoint.x, tickPoint.y)
  }
  ctx.stroke()

  ctx.font = unit * 3.5 + "px monospace"

  // Range rings carry the frequency they stand for, read back through the same mapping.
  // Under the ring, not above it, or the top one collides with the L bearing label.
  ctx.textAlign = "left"
  ctx.textBaseline = "top"
  ctx.fillStyle = H.rgba(d.accent, 0.34)
  for (var ring = 1; ring < rangeSteps; ring++) {
    var ringRange = ring / rangeSteps
    var ringBand = (ringRange / outerRange - RANGE_NEAR) / RANGE_SPAN * Math.max(1, bands.length - 1)
    var label = hzLabel(bandHz(d.bandEdges, ringBand + 0.5))
    if (label === "") continue
    var ringPoint = project(0.75, ringRange, 0)
    ctx.fillText(label, ringPoint.x + unit, ringPoint.y + unit / 2)
  }

  if (d.playing && bestBand >= 0 && s.crtSpawnClock >= 0.24 && (beatEdge || localOnset)) {
    addEcho(s, bestBand, bands.length, Math.max(bestLevel, beat), d.bandsStereo,
      d.analysis ? d.analysis.db_floor : -72, outerRange)
    if (secondBand >= 0 && bandLevels[secondBand] > 0.16 && secondScore > bestScore * 0.32
        && (beatEdge || bandRises[secondBand] > onsetThreshold * 0.75)) {
      addEcho(s, secondBand, bands.length, Math.max(bandLevels[secondBand], beat * 0.82),
        d.bandsStereo, d.analysis ? d.analysis.db_floor : -72, outerRange)
    }
    s.crtSpawnClock = 0
  }
  // Targets appear only after the sweep reaches them and expire after one round trip.
  var echoDecay = Math.exp(-dt / 1.75)
  for (var echoIndex = s.crtEchoes.length - 1; echoIndex >= 0; echoIndex--) {
    var echo = s.crtEchoes[echoIndex]
    echo.lit *= echoDecay
    if (echo.pulseProgress >= 0) echo.pulseProgress += dt / ECHO_PULSE_SECONDS
    if (echo.pulseProgress < 0 && waveRange >= echo.range && waveRange - echo.range < waveTravel) {
      echo.pulseProgress = 0; echo.lit = echo.strength
    }
    var scanDistance = (s.crtSweep - echo.azimuth + 2) % 2
    if (scanDistance <= dt * s.crtSweepSpeed + 0.012) {
      echo.lit = echo.strength
    }
    if (echo.pulseProgress >= 1) s.crtEchoes.splice(echoIndex, 1)
  }
  var echoes = s.crtEchoes.slice().sort(function(a, b) { return b.depth - a.depth })
  for (var target = 0; target < echoes.length; target++) {
    var echo = echoes[target]
    var progress = Math.max(0, echo.pulseProgress), fade = 1 - progress * progress
    var dotExpansion = Math.sin(Math.PI * progress)
    var ground = project(echo.azimuth, echo.range, 0)
    var point = project(echo.azimuth, echo.range, echo.strength * scopeElevation)
    var echoX = point.x, echoY = point.y
    var alpha = fade * Math.max(ECHO_IDLE_GLOW, echo.lit)
    var arm = unit * (1 + echo.strength) * point.scale
    ctx.strokeStyle = H.rgba(d.accent, alpha * 0.34)
    ctx.lineWidth = point.scale
    ctx.beginPath()
    ctx.moveTo(ground.x - arm, ground.y); ctx.lineTo(ground.x, ground.y - arm / 2)
    ctx.lineTo(ground.x + arm, ground.y); ctx.lineTo(ground.x, ground.y + arm / 2)
    ctx.closePath(); ctx.moveTo(ground.x, ground.y); ctx.lineTo(echoX, echoY)
    ctx.stroke()
    if (echo.pulseProgress >= 0) {
      ctx.strokeStyle = H.rgba(d.accent, alpha * (1 - progress))
      ctx.beginPath(); ctx.arc(echoX, echoY, arm + progress * h / rangeSteps * point.scale,
        0, Math.PI * 2); ctx.stroke()
    }
    ctx.fillStyle = H.mixColor(d.accent, d.foreground, 0.20 + echo.strength * 0.48,
      fade * (0.24 + echo.lit * 0.72))
    ctx.beginPath(); ctx.arc(echoX, echoY, (0.8 + echo.strength * 1.4) * point.scale * (1 + dotExpansion),
      0, Math.PI * 2); ctx.fill()
  }

  // A vertical phosphor beam and short afterglow scan the full stereo field.
  var beamPulse = d.playing ? 1 + H.bandAvg(d.bands || [], 0, 5) * 0.6 + beat * 0.4 : 1
  var beamHighlight = (beamPulse - 1) / rangeSteps
  var tailCount = 10, tailStep = unit * 1.1 / scopeWidth
  var sweepNear = center
  for (var tail = tailCount; tail >= 0; tail--) {
    var sweepFar = project(s.crtSweep - tail * tailStep, outerRange, 0)
    var sweepAlpha = (0.025 + (tailCount - tail) / tailCount * 0.27) * beamPulse
    ctx.strokeStyle = H.mixColor(d.accent, d.foreground, beamHighlight, sweepAlpha)
    ctx.lineWidth = (tail === 0 ? 1.6 : 1) * beamPulse
    ctx.beginPath(); ctx.moveTo(sweepFar.x, sweepFar.y)
    ctx.lineTo(sweepNear.x, sweepNear.y); ctx.stroke()
  }
  ctx.strokeStyle = H.mixColor(d.accent, d.foreground, beamHighlight, 0.32 * beamPulse)
  ctx.lineWidth = unit / 2 * beamPulse
  ctx.beginPath(); ctx.moveTo(sweepNear.x, sweepNear.y)
  ctx.lineTo(sweepFar.x, sweepFar.y); ctx.stroke()
  ctx.fillStyle = H.mixColor(d.accent, d.foreground, beamHighlight, Math.min(1, 0.56 * beamPulse))
  ctx.fillRect(sweepFar.x - unit / 2, sweepFar.y, unit, unit)
  ctx.fillRect(sweepNear.x - unit / 2, sweepNear.y - unit / 2, unit, unit)
}

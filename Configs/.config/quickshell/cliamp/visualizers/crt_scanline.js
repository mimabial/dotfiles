.pragma library
.import "helpers.js" as VisualizerHelpers

var RANGE_NEAR = 0.05
var RANGE_SPAN = 0.90
var MAX_ECHOES = 6
var ECHO_PULSE_SECONDS = 0.55
var ECHO_IDLE_GLOW = 0.06
var WAVE_BEATS = 4

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

function addEcho(animationState, band, bandCount, strength, stereo, dbFloor, outerRange) {
  var frequency = bandCount > 1 ? band / (bandCount - 1) : 0.5
  var pan = stereoBearing(stereo, band, dbFloor)
  var distributed = (animationState.crtSequence * 0.61803398875 + frequency * 0.29) % 1
  var bearing = clamp(distributed * 0.88 + pan * 0.12, 0.02, 0.98)
  animationState.crtSequence++
  var range = (RANGE_NEAR + frequency * RANGE_SPAN) * outerRange
  for (var index = 0; index < animationState.crtEchoes.length; index++) {
    var existing = animationState.crtEchoes[index]
    if (Math.abs(existing.bearing - bearing) < 0.04 && Math.abs(existing.range - range) < 0.07) {
      if (existing.pulseProgress < 0) existing.strength = Math.max(existing.strength, clamp(strength, 0.25, 1))
      existing.lit = Math.max(existing.lit, 0.08)
      return
    }
  }
  if (animationState.crtEchoes.length >= MAX_ECHOES) return
  var echo = {
    bearing: bearing,
    range: range,
    azimuth: bearing * 2,
    depth: 0.5 - Math.sin(bearing * Math.PI * 2) * range / 2,
    strength: clamp(strength, 0.25, 1),
    lit: ECHO_IDLE_GLOW,
    pulseProgress: -1
  }
  animationState.crtEchoes.push(echo)
}

function render(canvas, frameData) {
  var width = frameData.width, height = frameData.height
  var unit = frameData.S, rangeSteps = 4, bearingSteps = rangeSteps * 3, perspectiveDepth = 1.8
  var scopeLeft = unit * 2, scopeRight = width - scopeLeft, scopeTop = unit * 1.5, scopeBottom = height - scopeLeft
  var scopeWidth = scopeRight - scopeLeft, scopeHeight = scopeBottom - scopeTop
  var scopeElevation = scopeHeight / 2
  function project(azimuth, range, elevation) {
    var angle = azimuth * Math.PI, radius = range / 2
    var scale = 1 / (1 + (0.5 - Math.sin(angle) * radius) * perspectiveDepth)
    return { x: width / 2 + Math.cos(angle) * radius * scopeWidth * scale,
      y: scopeTop + (scopeHeight - elevation) * scale, scale: scale }
  }
  var center = project(0, 0, 0), rim = []
  var bands = frameData.rawBands && frameData.rawBands.length ? frameData.rawBands : (frameData.bands || [])
  var animationState = frameData.state, now = Date.now()
  if (animationState.crtLinear !== true) {
    animationState.crtLinear = true
    animationState.crtLastTime = now; animationState.crtSweep = 0
    animationState.crtSweepSpeed = 0.46; animationState.crtBeatPeriod = 0; animationState.crtLastBeatTime = 0
    animationState.crtEchoes = []; animationState.crtWaveProgress = 1; animationState.crtWaveSpeed = animationState.crtSweepSpeed
    animationState.crtPrevBands = []; animationState.crtSpawnClock = 0; animationState.crtFluxFloor = 0
    animationState.crtPrevBeat = 0; animationState.crtSequence = 0
  }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.crtLastTime) / 1000))
  animationState.crtLastTime = now; animationState.crtSpawnClock += elapsedSeconds

  var beat = clamp(frameData.beatDrop, 0, 1)
  var beatEdge = beat > 0.72 && animationState.crtPrevBeat <= 0.72
  animationState.crtPrevBeat = beat
  if (frameData.playing && beatEdge) {
    if (animationState.crtLastBeatTime > 0) {
      var beatInterval = now - animationState.crtLastBeatTime
      if (beatInterval >= 280 && beatInterval <= 1200) {
        if (animationState.crtBeatPeriod <= 0) animationState.crtBeatPeriod = beatInterval
        else if (beatInterval > animationState.crtBeatPeriod * 0.65 && beatInterval < animationState.crtBeatPeriod * 1.45)
          animationState.crtBeatPeriod += (beatInterval - animationState.crtBeatPeriod) * 0.22
      }
    }
    animationState.crtLastBeatTime = now
  }
  var beatLockFresh = animationState.crtBeatPeriod > 0
    && now - animationState.crtLastBeatTime < Math.max(3500, animationState.crtBeatPeriod * 6)
  var targetSweepSpeed = beatLockFresh
    ? clamp(1 / (animationState.crtBeatPeriod / 1000 * 4), 0.21, 0.76) : 0.46
  animationState.crtSweepSpeed += (targetSweepSpeed - animationState.crtSweepSpeed) * (1 - Math.exp(-elapsedSeconds / 0.85))

  animationState.crtSweep = (animationState.crtSweep + elapsedSeconds * animationState.crtSweepSpeed) % 2

  var bestBand = -1, bestScore = 0, bestRise = 0, bestLevel = 0
  var bandScores = [], bandRises = [], bandLevels = []
  for (var band = 0; band < bands.length; band++) {
    var level = clamp(bands[band], 0, 1)
    var previous = Number(animationState.crtPrevBands[band] || 0)
    var rise = Math.max(0, level - previous)
    var score = rise * 3.2 + level * 0.18
    bandScores[band] = score; bandRises[band] = rise; bandLevels[band] = level
    if (score > bestScore) {
      bestBand = band; bestScore = score; bestRise = rise; bestLevel = level
    }
    animationState.crtPrevBands[band] = level
  }
  var secondBand = -1, secondScore = 0
  for (var candidate = 0; candidate < bands.length; candidate++) {
    if (Math.abs(candidate - bestBand) >= 3 && bandScores[candidate] > secondScore) {
      secondBand = candidate; secondScore = bandScores[candidate]
    }
  }
  var onsetThreshold = Math.max(0.065, animationState.crtFluxFloor * 2.4)
  var localOnset = bestRise > onsetThreshold && bestLevel > 0.22
  animationState.crtFluxFloor += (bestRise - animationState.crtFluxFloor) * (1 - Math.exp(-elapsedSeconds / 1.4))

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.surface, 0.32)
  for (var scanY = 0; scanY < height; scanY += 2) canvas.fillRect(0, scanY, width, 1)
  canvas.lineWidth = 1

  var planeDepth = 1 + perspectiveDepth / 2
  function ringPath(radius) {
    var radialDepth = radius * perspectiveDepth / 2
    var ellipseDepth = planeDepth * planeDepth - radialDepth * radialDepth
    canvas.save(); canvas.translate(width / 2, scopeTop + scopeHeight * planeDepth / ellipseDepth)
    canvas.scale(scopeWidth * radius / (2 * Math.sqrt(ellipseDepth)), scopeHeight * radialDepth / ellipseDepth)
    canvas.moveTo(1, 0); canvas.arc(0, 0, 1, 0, Math.PI * 2); canvas.restore()
  }
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.26)
  canvas.beginPath()
  var outerSteps = Math.ceil(2 * planeDepth * rangeSteps / perspectiveDepth) - 1
  for (var row = 1; row <= outerSteps; row++) ringPath(row / rangeSteps)
  canvas.stroke()
  var outerRange = outerSteps / rangeSteps, waveStart = animationState.crtWaveProgress
  if (frameData.playing && (beatEdge || localOnset) && animationState.crtWaveProgress >= 1) {
    animationState.crtWaveProgress = 0; waveStart = 0
    animationState.crtWaveSpeed = beatLockFresh ? 1000 / (animationState.crtBeatPeriod * WAVE_BEATS) : animationState.crtSweepSpeed
  }
  animationState.crtWaveProgress = Math.min(1, animationState.crtWaveProgress + elapsedSeconds * animationState.crtWaveSpeed)
  var waveRange = animationState.crtWaveProgress * outerRange, waveTravel = (animationState.crtWaveProgress - waveStart) * outerRange
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, Math.min(1, (outerRange - waveRange) * rangeSteps) * 0.56)
  canvas.lineWidth = unit
  canvas.beginPath(); if (animationState.crtWaveProgress < 1) ringPath(waveRange); canvas.stroke()
  canvas.lineWidth = 1

  canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, 0.20)
  for (var column = 0; column < bearingSteps; column++) {
    var edge = project(column * 2 / bearingSteps, outerRange, 0)
    rim.push(edge)
    var dx = edge.x - center.x, dy = edge.y - center.y
    var dotSteps = Math.ceil(Math.max(Math.abs(dx), Math.abs(dy)) / (unit * 2))
    var visibleSteps = dotSteps * Math.min(1,
      dx === 0 ? 1 : (dx > 0 ? width - 1 - center.x : -center.x) / dx,
      dy === 0 ? 1 : (dy > 0 ? height - 1 - center.y : -center.y) / dy)
    for (var dot = 1; dot < visibleSteps; dot++)
      canvas.fillRect(Math.round(center.x + dx * dot / dotSteps), Math.round(center.y + dy * dot / dotSteps), 1, 1)
  }

  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.38)
  canvas.beginPath()
  for (var tick = 0; tick < bearingSteps; tick++) {
    var tickPoint = project(tick * 2 / bearingSteps, outerRange - (tick % (bearingSteps / 4) === 0 ? unit * 2 : unit) / scopeHeight, 0)
    canvas.moveTo(rim[tick].x, rim[tick].y); canvas.lineTo(tickPoint.x, tickPoint.y)
  }
  canvas.stroke()

  canvas.font = unit * 3.5 + "px monospace"

  canvas.textAlign = "left"
  canvas.textBaseline = "top"
  canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, 0.34)
  for (var ring = 1; ring < rangeSteps; ring++) {
    var ringRange = ring / rangeSteps
    var ringBand = (ringRange / outerRange - RANGE_NEAR) / RANGE_SPAN * Math.max(1, bands.length - 1)
    var label = hzLabel(bandHz(frameData.bandEdges, ringBand + 0.5))
    if (label === "") continue
    var ringPoint = project(0.75, ringRange, 0)
    canvas.fillText(label, ringPoint.x + unit, ringPoint.y + unit / 2)
  }

  if (frameData.playing && bestBand >= 0 && animationState.crtSpawnClock >= 0.24 && (beatEdge || localOnset)) {
    addEcho(animationState, bestBand, bands.length, Math.max(bestLevel, beat), frameData.bandsStereo,
      frameData.analysis ? frameData.analysis.db_floor : -72, outerRange)
    if (secondBand >= 0 && bandLevels[secondBand] > 0.16 && secondScore > bestScore * 0.32
        && (beatEdge || bandRises[secondBand] > onsetThreshold * 0.75)) {
      addEcho(animationState, secondBand, bands.length, Math.max(bandLevels[secondBand], beat * 0.82),
        frameData.bandsStereo, frameData.analysis ? frameData.analysis.db_floor : -72, outerRange)
    }
    animationState.crtSpawnClock = 0
  }
  var echoDecay = Math.exp(-elapsedSeconds / 1.75)
  for (var echoIndex = animationState.crtEchoes.length - 1; echoIndex >= 0; echoIndex--) {
    var echo = animationState.crtEchoes[echoIndex]
    echo.lit *= echoDecay
    if (echo.pulseProgress >= 0) echo.pulseProgress += elapsedSeconds / ECHO_PULSE_SECONDS
    if (echo.pulseProgress < 0 && waveRange >= echo.range && waveRange - echo.range < waveTravel) {
      echo.pulseProgress = 0; echo.lit = echo.strength
    }
    var scanDistance = (animationState.crtSweep - echo.azimuth + 2) % 2
    if (scanDistance <= elapsedSeconds * animationState.crtSweepSpeed + 0.012) {
      echo.lit = echo.strength
    }
    if (echo.pulseProgress >= 1) animationState.crtEchoes.splice(echoIndex, 1)
  }
  var echoes = animationState.crtEchoes.slice().sort(function(a, b) { return b.depth - a.depth })
  for (var target = 0; target < echoes.length; target++) {
    var echo = echoes[target]
    var progress = Math.max(0, echo.pulseProgress), fade = 1 - progress * progress
    var dotExpansion = Math.sin(Math.PI * progress)
    var ground = project(echo.azimuth, echo.range, 0)
    var point = project(echo.azimuth, echo.range, echo.strength * scopeElevation)
    var echoX = point.x, echoY = point.y
    var alpha = fade * Math.max(ECHO_IDLE_GLOW, echo.lit)
    var arm = unit * (1 + echo.strength) * point.scale
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, alpha * 0.34)
    canvas.lineWidth = point.scale
    canvas.beginPath()
    canvas.moveTo(ground.x - arm, ground.y); canvas.lineTo(ground.x, ground.y - arm / 2)
    canvas.lineTo(ground.x + arm, ground.y); canvas.lineTo(ground.x, ground.y + arm / 2)
    canvas.closePath(); canvas.moveTo(ground.x, ground.y); canvas.lineTo(echoX, echoY)
    canvas.stroke()
    if (echo.pulseProgress >= 0) {
      canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, alpha * (1 - progress))
      canvas.beginPath(); canvas.arc(echoX, echoY, arm + progress * height / rangeSteps * point.scale,
        0, Math.PI * 2); canvas.stroke()
    }
    canvas.fillStyle = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, 0.20 + echo.strength * 0.48,
      fade * (0.24 + echo.lit * 0.72))
    canvas.beginPath(); canvas.arc(echoX, echoY, (0.8 + echo.strength * 1.4) * point.scale * (1 + dotExpansion),
      0, Math.PI * 2); canvas.fill()
  }

  var beamPulse = frameData.playing ? 1 + VisualizerHelpers.bandAvg(frameData.bands || [], 0, 5) * 0.6 + beat * 0.4 : 1
  var beamHighlight = (beamPulse - 1) / rangeSteps
  var tailCount = 10, tailStep = unit * 1.1 / scopeWidth
  var sweepNear = center
  for (var tail = tailCount; tail >= 0; tail--) {
    var sweepFar = project(animationState.crtSweep - tail * tailStep, outerRange, 0)
    var sweepAlpha = (0.025 + (tailCount - tail) / tailCount * 0.27) * beamPulse
    canvas.strokeStyle = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, beamHighlight, sweepAlpha)
    canvas.lineWidth = (tail === 0 ? 1.6 : 1) * beamPulse
    canvas.beginPath(); canvas.moveTo(sweepFar.x, sweepFar.y)
    canvas.lineTo(sweepNear.x, sweepNear.y); canvas.stroke()
  }
  canvas.strokeStyle = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, beamHighlight, 0.32 * beamPulse)
  canvas.lineWidth = unit / 2 * beamPulse
  canvas.beginPath(); canvas.moveTo(sweepNear.x, sweepNear.y)
  canvas.lineTo(sweepFar.x, sweepFar.y); canvas.stroke()
  canvas.fillStyle = VisualizerHelpers.mixColor(frameData.accent, frameData.foreground, beamHighlight, Math.min(1, 0.56 * beamPulse))
  canvas.fillRect(sweepFar.x - unit / 2, sweepFar.y, unit, unit)
  canvas.fillRect(sweepNear.x - unit / 2, sweepNear.y - unit / 2, unit, unit)
}

// CRT Linear Radar Scope — stereo-positioned audio transients scanned across a range grid.
.pragma library
.import "helpers.js" as H

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

function addEcho(s, band, bandCount, strength, stereo, dbFloor) {
  var frequency = bandCount > 1 ? band / (bandCount - 1) : 0.5
  var pan = stereoBearing(stereo, band, dbFloor)
  var distributed = (s.crtSequence * 0.61803398875 + frequency * 0.29) % 1
  var bearing = clamp(distributed * 0.88 + pan * 0.12, 0.02, 0.98)
  s.crtSequence++
  var range = 0.20 + Math.pow(frequency, 0.72) * 0.70
  for (var index = 0; index < s.crtEchoes.length; index++) {
    var existing = s.crtEchoes[index]
    if (Math.abs(existing.bearing - bearing) < 0.04 && Math.abs(existing.range - range) < 0.07) {
      existing.strength = Math.max(existing.strength, clamp(strength, 0.25, 1))
      existing.scanTravel = 0; existing.lit = Math.max(existing.lit, 0.08)
      s.crtEchoes.splice(index, 1); s.crtEchoes.push(existing)
      return
    }
  }
  var echo = {
    bearing: bearing,
    range: range,
    strength: clamp(strength, 0.25, 1),
    scanTravel: 0,
    lit: 0.06
  }
  s.crtEchoes.push(echo)
  while (s.crtEchoes.length > 12) s.crtEchoes.shift()
}

function render(ctx, d) {
  var w = d.width, h = d.height
  var scopeLeft = 4, scopeRight = w - 4, scopeTop = 3, scopeBottom = h - 4
  var scopeWidth = scopeRight - scopeLeft, scopeHeight = scopeBottom - scopeTop
  var bands = d.rawBands && d.rawBands.length ? d.rawBands : (d.bands || [])
  var s = d.state, now = Date.now()
  if (s.crtLinear !== true) {
    s.crtLinear = true
    s.crtLastTime = now; s.crtSweep = 0; s.crtSweepDirection = 1
    s.crtSweepSpeed = 0.46; s.crtBeatPeriod = 0; s.crtLastBeatTime = 0
    s.crtEchoes = []
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

  s.crtSweep += dt * s.crtSweepSpeed * s.crtSweepDirection
  if (s.crtSweep > 1) {
    s.crtSweep = 2 - s.crtSweep
    s.crtSweepDirection = -1
  } else if (s.crtSweep < 0) {
    s.crtSweep = -s.crtSweep
    s.crtSweepDirection = 1
  }

  // Phosphor raster and a rectangular bearing/range graticule.
  ctx.fillStyle = H.rgba(d.surface, 0.32)
  for (var scanY = 0; scanY < h; scanY += 2) ctx.fillRect(0, scanY, w, 1)
  ctx.strokeStyle = H.rgba(d.accent, 0.16); ctx.lineWidth = 1
  ctx.beginPath()
  for (var column = 0; column <= 12; column++) {
    var gridX = scopeLeft + scopeWidth * column / 12
    ctx.moveTo(gridX, scopeTop); ctx.lineTo(gridX, scopeBottom)
  }
  for (var row = 0; row <= 4; row++) {
    var gridY = scopeTop + scopeHeight * row / 4
    ctx.moveTo(scopeLeft, gridY); ctx.lineTo(scopeRight, gridY)
  }
  ctx.stroke()

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
  if (d.playing && bestBand >= 0 && s.crtSpawnClock >= 0.24 && (beatEdge || localOnset)) {
    addEcho(s, bestBand, bands.length, Math.max(bestLevel, beat), d.bandsStereo,
      d.analysis ? d.analysis.db_floor : -72)
    if (secondBand >= 0 && bandLevels[secondBand] > 0.16 && secondScore > bestScore * 0.32
        && (beatEdge || bandRises[secondBand] > onsetThreshold * 0.75)) {
      addEcho(s, secondBand, bands.length, Math.max(bandLevels[secondBand], beat * 0.82),
        d.bandsStereo, d.analysis ? d.analysis.db_floor : -72)
    }
    s.crtSpawnClock = 0
  }
  // Targets appear only after the sweep reaches them and expire after one round trip.
  for (var echoIndex = s.crtEchoes.length - 1; echoIndex >= 0; echoIndex--) {
    var echo = s.crtEchoes[echoIndex]
    echo.scanTravel = Number(echo.scanTravel || 0) + dt * s.crtSweepSpeed
    echo.lit *= Math.exp(-dt / 1.75)
    if (Math.abs(echo.bearing - s.crtSweep) <= dt * s.crtSweepSpeed + 0.012) {
      echo.lit = echo.strength
    }
    if (echo.scanTravel >= 2) { s.crtEchoes.splice(echoIndex, 1); continue }
    if (echo.lit < 0.025) continue
    var fade = Math.min(1, (2 - echo.scanTravel) / Math.max(0.1, s.crtSweepSpeed * 0.8))
    var echoX = scopeLeft + echo.bearing * scopeWidth
    var echoY = scopeBottom - echo.range * scopeHeight
    var alpha = fade * echo.lit
    ctx.strokeStyle = H.rgba(d.accent, 0.20 + alpha * 0.64)
    ctx.lineWidth = 1 + echo.strength * 1.2
    ctx.beginPath(); ctx.moveTo(echoX - 2.5 - echo.strength * 2, echoY)
    ctx.lineTo(echoX + 2.5 + echo.strength * 2, echoY); ctx.stroke()
    ctx.fillStyle = H.mixColor(d.accent, d.foreground, 0.20 + echo.strength * 0.48,
      0.24 + alpha * 0.72)
    ctx.beginPath(); ctx.arc(echoX, echoY, 0.8 + echo.strength * 1.4,
      0, Math.PI * 2); ctx.fill()
  }

  // A vertical phosphor beam and short afterglow scan the full stereo field.
  var sweepX = scopeLeft + s.crtSweep * scopeWidth
  for (var tail = 10; tail >= 0; tail--) {
    var tailX = sweepX - s.crtSweepDirection * tail * 2.2
    if (tailX < scopeLeft || tailX > scopeRight) continue
    var sweepAlpha = 0.025 + (10 - tail) / 10 * 0.27
    ctx.strokeStyle = H.rgba(d.accent, sweepAlpha)
    ctx.lineWidth = tail === 0 ? 1.6 : 1
    ctx.beginPath(); ctx.moveTo(tailX, scopeTop)
    ctx.lineTo(tailX, scopeBottom); ctx.stroke()
  }
  ctx.fillStyle = H.rgba(d.accent, 0.56)
  ctx.fillRect(sweepX - 1, scopeTop, 2, 2)
  ctx.fillRect(sweepX - 1, scopeBottom - 1, 2, 2)
}

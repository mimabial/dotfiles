// Port of cliamp vis_classic_peak.go.
.pragma library
.import "helpers.js" as H

var GRAVITY = 9.5
var LAUNCH_BASE = 0.8
var LAUNCH_GAIN = 1.4
var LAUNCH_MAX = 1.7
var APEX_HOLD = 0.08
var MAX_HEIGHT = 1.0
var EPSILON = 0.01
var RISE_RATE = 34.0
var FALL_RATE = 10.0
var BAR_CHARS = 1
var BAR_GAP_CHARS = 1
var FALLBACK_DT = 1 / 60
var MIN_FPS = 24
var MAX_FPS = 60

function colsForWidth(cols) {
  return Math.max(1, Math.floor((cols + BAR_GAP_CHARS) / (BAR_CHARS + BAR_GAP_CHARS)))
}

function levelToPower(level, dbFloor) {
  return level > 0 ? Math.pow(10, (1 - level) * dbFloor / 10) : 0
}

function powerToLevel(power, dbFloor) {
  return Math.min(1, Math.max(0, 1 - 10 * Math.log10(power) / dbFloor))
}

function bandsForCols(bands, cols, dbFloor) {
  if (cols >= bands.length) return H.resampleBandsLinear(bands, cols)
  var bandsPerCol = bands.length / cols
  var out = new Array(cols)
  for (var col = 0; col < cols; col++) {
    var start = col * bandsPerCol, end = Math.min(bands.length, start + bandsPerCol), power = 0
    for (var band = Math.floor(start); band < end; band++) {
      var overlap = Math.min(end, band + 1) - Math.max(start, band)
      power += levelToPower(bands[band], dbFloor) * overlap
    }
    out[col] = powerToLevel(power, dbFloor)
  }
  return out
}

function frameInterval(height) {
  return 1000 / Math.min(MAX_FPS, Math.max(MIN_FPS, LAUNCH_MAX * height))
}

function animating(state) {
  if (!state.peakBar) return false
  for (var i = 0; i < state.peakBar.length; i++) {
    if (state.peakBar[i] > EPSILON || state.peakPos[i] > state.peakBar[i] + EPSILON) return true
  }
  return false
}

function step(current, target, dt) {
  return current + (target - current) * (1 - Math.exp(-(target > current ? RISE_RATE : FALL_RATE) * dt))
}

function onEnter(state) {
  state.peakBar = null
  state.peakPos = null
  state.peakVel = null
  state.peakHold = null
  state.peakLast = 0
}

function render(ctx, d) {
  var w = d.width, h = d.height
  var charW = 6
  var bars = colsForWidth(Math.floor(w / charW))
  var levels = bandsForCols(d.bandsFine, bars, d.analysis.db_floor)
  if (!levels.length || h < 1) return
  var s = d.state
  if (!s.peakBar || s.peakBar.length !== bars) {
    s.peakBar = levels.slice()
    s.peakPos = levels.slice()
    s.peakVel = new Array(bars).fill(0)
    s.peakHold = new Array(bars).fill(0)
    s.peakLast = 0
  }
  var barPos = s.peakBar, peakPos = s.peakPos, peakVel = s.peakVel, peakHold = s.peakHold

  // Go integrates against wall-clock elapsed time, clamping a long gap (pause, sleep,
  // stalled frame) down to a single frame rather than one huge step.
  var now = Date.now()
  var dt = s.peakLast > 0 ? (now - s.peakLast) / 1000.0 : FALLBACK_DT
  if (dt <= 0 || dt > 10 * FALLBACK_DT) dt = FALLBACK_DT
  s.peakLast = now

  var i
  // sync: a landed cap relaunches when the band rises past it.
  for (i = 0; i < bars; i++) {
    if (peakVel[i] === 0 && peakPos[i] <= barPos[i] + EPSILON && levels[i] > peakPos[i]) {
      peakVel[i] = Math.min(LAUNCH_MAX, LAUNCH_BASE + LAUNCH_GAIN * (levels[i] - peakPos[i]))
      peakPos[i] = levels[i]
      peakHold[i] = 0
    }
  }

  // advance: ease the body toward the band, then integrate the cap.
  for (i = 0; i < bars; i++) {
    barPos[i] = step(barPos[i], levels[i], dt)

    if (peakHold[i] > 0) {
      peakHold[i] = Math.max(0, peakHold[i] - dt)
      if (peakHold[i] > 0) continue
    }

    var prevVel = peakVel[i]
    peakPos[i] += peakVel[i] * dt
    peakVel[i] -= GRAVITY * dt
    if (peakPos[i] > MAX_HEIGHT) peakPos[i] = MAX_HEIGHT

    if (prevVel > 0 && peakVel[i] <= 0 && peakPos[i] > barPos[i] + EPSILON) {
      peakVel[i] = 0
      peakHold[i] = APEX_HOLD
      continue
    }
    if (peakPos[i] <= barPos[i]) {
      peakPos[i] = barPos[i]
      peakVel[i] = 0
      peakHold[i] = 0
    }
  }

  var tiers = H.playerTiers(d)
  var barPx = charW * BAR_CHARS
  var stepPx = charW * (BAR_CHARS + BAR_GAP_CHARS)

  // Rows outer, bars inner: the tier depends only on the row, so every bar shares one
  // fillStyle assignment per row instead of one per bar.
  for (var y = 0; y < h; y++) {
    ctx.fillStyle = tiers[H.specTag(y / h)]
    for (var b = 0; b < bars; b++) {
      if (barPos[b] * h > y) ctx.fillRect(b * stepPx, h - 1 - y, barPx, 1)
    }
  }

  // A cap only shows once it clears the body by half a rendering unit.
  var minGap = Math.max(EPSILON, 0.5 / h)
  for (var c = 0; c < bars; c++) {
    if (peakPos[c] <= barPos[c] + minGap) continue
    var capNorm = Math.min(MAX_HEIGHT, peakPos[c])
    ctx.fillStyle = tiers[H.specTag(capNorm)]
    ctx.fillRect(c * stepPx, Math.max(0, Math.min(h - 2, h - Math.round(capNorm * h))), barPx, 2)
  }
}

.pragma library
.import "helpers.js" as VisualizerHelpers

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
  if (cols >= bands.length) return VisualizerHelpers.resampleBandsLinear(bands, cols)
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

function step(current, target, elapsedSeconds) {
  return current + (target - current) * (1 - Math.exp(-(target > current ? RISE_RATE : FALL_RATE) * elapsedSeconds))
}

function onEnter(state) {
  state.peakBar = null
  state.peakPos = null
  state.peakVel = null
  state.peakHold = null
  state.peakLast = 0
}

function render(canvas, frameData) {
  var width = frameData.width, height = frameData.height
  var charW = 6
  var bars = colsForWidth(Math.floor(width / charW))
  var levels = bandsForCols(frameData.bandsFine, bars, frameData.analysis.db_floor)
  if (!levels.length || height < 1) return
  var animationState = frameData.state
  if (!animationState.peakBar || animationState.peakBar.length !== bars) {
    animationState.peakBar = levels.slice()
    animationState.peakPos = levels.slice()
    animationState.peakVel = new Array(bars).fill(0)
    animationState.peakHold = new Array(bars).fill(0)
    animationState.peakLast = 0
  }
  var barPos = animationState.peakBar, peakPos = animationState.peakPos, peakVel = animationState.peakVel, peakHold = animationState.peakHold

  var now = Date.now()
  var elapsedSeconds = animationState.peakLast > 0 ? (now - animationState.peakLast) / 1000.0 : FALLBACK_DT
  if (elapsedSeconds <= 0 || elapsedSeconds > 10 * FALLBACK_DT) elapsedSeconds = FALLBACK_DT
  animationState.peakLast = now

  var i
  for (i = 0; i < bars; i++) {
    if (peakVel[i] === 0 && peakPos[i] <= barPos[i] + EPSILON && levels[i] > peakPos[i]) {
      peakVel[i] = Math.min(LAUNCH_MAX, LAUNCH_BASE + LAUNCH_GAIN * (levels[i] - peakPos[i]))
      peakPos[i] = levels[i]
      peakHold[i] = 0
    }
  }

  for (i = 0; i < bars; i++) {
    barPos[i] = step(barPos[i], levels[i], elapsedSeconds)

    if (peakHold[i] > 0) {
      peakHold[i] = Math.max(0, peakHold[i] - elapsedSeconds)
      if (peakHold[i] > 0) continue
    }

    var prevVel = peakVel[i]
    peakPos[i] += peakVel[i] * elapsedSeconds
    peakVel[i] -= GRAVITY * elapsedSeconds
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

  var tiers = VisualizerHelpers.playerTiers(frameData)
  var barPx = charW * BAR_CHARS
  var stepPx = charW * (BAR_CHARS + BAR_GAP_CHARS)

  for (var y = 0; y < height; y++) {
    canvas.fillStyle = tiers[VisualizerHelpers.specTag(y / height)]
    for (var b = 0; b < bars; b++) {
      if (barPos[b] * height > y) canvas.fillRect(b * stepPx, height - 1 - y, barPx, 1)
    }
  }

  var minGap = Math.max(EPSILON, 0.5 / height)
  for (var c = 0; c < bars; c++) {
    if (peakPos[c] <= barPos[c] + minGap) continue
    var capNorm = Math.min(MAX_HEIGHT, peakPos[c])
    canvas.fillStyle = tiers[VisualizerHelpers.specTag(capNorm)]
    canvas.fillRect(c * stepPx, Math.max(0, Math.min(height - 2, height - Math.round(capNorm * height))), barPx, 2)
  }
}

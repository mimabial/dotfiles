// Peaks — exact cliamp vis_classic_peak.go: exponentially smoothed bar bodies with
// peak caps that launch on a rise, hang at the apex, then fall under gravity
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
var BAR_W = 1      // characters per bar
var BAR_GAP = 1    // characters between bars
var TICK = 1 / 60  // tickClassicPeak: the dt fallback when elapsed time is unusable

function colsForWidth(cols) {
  return Math.max(1, Math.floor((cols + BAR_GAP) / (BAR_W + BAR_GAP)))
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
  if (bars < 1 || h < 1) return

  var levels = H.resampleBandsLinear(d.bands, bars)
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
  var dt = s.peakLast > 0 ? (now - s.peakLast) / 1000.0 : TICK
  if (dt <= 0 || dt > 10 * TICK) dt = TICK
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

  var tiers = H.specTiers(d)
  var barPx = charW * BAR_W
  var stepPx = charW * (BAR_W + BAR_GAP)

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

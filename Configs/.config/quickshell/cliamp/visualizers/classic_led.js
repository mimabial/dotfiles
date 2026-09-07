// ClassicLED — exact cliamp vis_classic_led.go: a Winamp-style LED matrix with
// fast-attack bodies and peak caps that hold at the apex then fall
.pragma library
.import "helpers.js" as H

var BAR_W = 2   // characters per bar
var BAR_GAP = 1
var FPS = 30    // classicLEDFPS: the dt fallback when elapsed time is unusable
var RISE_RATE = 60.0
var FALL_RATE = 16.0
var PEAK_HOLD = 0.45
var PEAK_FALL = 0.55

function barCount(cols) {
  return Math.max(1, Math.floor((cols + BAR_GAP) / (BAR_W + BAR_GAP)))
}

function onEnter(state) {
  state.ledBody = null
  state.ledPeak = null
  state.ledHold = null
  state.ledLast = 0
}

function render(ctx, d) {
  var w = d.width, h = d.height
  var charW = 6
  var charH = 10
  var numCols = Math.floor(w / charW)
  var rows = Math.floor(h / charH)
  var bars = barCount(numCols)
  if (rows < 1 || bars < 1) return

  var levels = H.resampleBandsLinear(d.bands, bars)
  var s = d.state
  if (!s.ledBody || s.ledBody.length !== bars) {
    s.ledBody = levels.slice()
    s.ledPeak = levels.slice()
    s.ledHold = new Array(bars).fill(0)
    s.ledLast = 0
  }
  var body = s.ledBody, peak = s.ledPeak, hold = s.ledHold

  var frameDt = 1 / FPS
  var now = Date.now()
  var dt = s.ledLast > 0 ? (now - s.ledLast) / 1000.0 : frameDt
  if (dt <= 0 || dt > 10 * frameDt) dt = frameDt
  s.ledLast = now

  for (var i = 0; i < bars; i++) {
    var target = levels[i] || 0
    body[i] += (target - body[i]) * (1 - Math.exp(-(target > body[i] ? RISE_RATE : FALL_RATE) * dt))
    if (body[i] >= peak[i]) {
      peak[i] = body[i]
      hold[i] = PEAK_HOLD
    } else if (hold[i] > 0) {
      hold[i] = Math.max(0, hold[i] - dt)
    } else {
      peak[i] = Math.max(body[i], peak[i] - PEAK_FALL * dt)
    }
  }

  var tiers = H.specTiers(d)
  var barPx = charW * BAR_W
  var stepPx = charW * (BAR_W + BAR_GAP)
  var halfH = Math.max(1, Math.round(charH / 2))
  // Go left-pads the row, so the matrix sits against the right edge.
  var padPx = Math.max(0, numCols - (bars * (BAR_W + BAR_GAP) - BAR_GAP)) * charW

  for (var b = 0; b < bars; b++) {
    var x = padPx + b * stepPx
    var lit = Math.floor(body[b] * rows + 1e-6)
    var peakSeg = Math.min(rows - 1, Math.floor(peak[b] * rows + 1e-6))
    // A cap only renders when it sits strictly above the body; otherwise it merges.
    var showPeak = peak[b] > body[b] + 0.5 / rows && peakSeg >= lit

    for (var seg = 0; seg < rows; seg++) {
      var rowY = h - (seg + 1) * charH
      if (seg < lit) {
        ctx.fillStyle = tiers[H.specTag(seg / rows)]
        ctx.fillRect(x, rowY + charH - halfH, barPx, halfH)   // ▄
      } else if (showPeak && seg === peakSeg) {
        ctx.fillStyle = tiers[H.specTag(seg / rows)]
        ctx.fillRect(x, rowY, barPx, halfH)                   // ▀
      }
    }
  }
}

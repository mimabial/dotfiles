.pragma library
.import "helpers.js" as VisualizerHelpers

var JOINTS = 13
var SEG = 1.5
var FLICK_STEPS = 8
var MAX_POWER = 1.4
var SWIRL_LIFE = 12
var SWIRL_POINTS = 14
var STANDOUT = 1.5
var REST = 20
var BASS_STEPS = 40
var QUIET = 0.02
var STRIP_PACE = 2.5
var ARC_STEPS = 64
var GAP = 36.0
var HALF_BODY = 6.3
var NOSE = 2.6
var TAIL_FIN = 1.0
var RADII = [2.5, 2.9, 2.9, 2.7, 2.4, 2.05, 1.75, 1.45, 1.2, 1.0, 0.85, 0.7, 0.6]
var PETALS = 6
var PETAL_SAMPLES = 64
var NOTCH_X = Math.cos(0.9)
var NOTCH_Y = Math.sin(0.9)
var NOTCH_SLOPE = Math.tan(0.28)
var NOTCH_INNER = 0.2

var WATER = 0
var DIM = 1
var PAD = 2
var RED = 3
var INK = 4
var GOLD = 5

var PATTERNS = [
  { body: RED, back: [0, INK, INK, 0, INK, INK, 0, 0, INK, INK, 0, INK, 0] },
  { body: INK, back: [0, RED, RED, 0, 0, RED, RED, RED, 0, 0, 0, 0, 0] }
]

var PETAL_WIDTHS = (function () {
  var widths = []
  for (var i = 0; i <= PETAL_SAMPLES; i++)
    widths.push(0.36 * Math.pow(Math.sin(Math.PI * Math.pow(i / PETAL_SAMPLES, 0.8)), 0.6))
  return widths
})()

function onEnter(state) {
  state.yinYang = null
}

function newOnset(from, to, k, floor, gap) {
  return { from: from, to: to, k: k, floor: floor, gap: gap, since: gap, mean: 0.03, dev: 0.02 }
}

function newDriver() {
  return {
    clock: { last: 0, pending: 0 }, w: 0, h: 0,
    angle: 0, loud: 0.3, mood: 0.3, bloom: 0.4, breath: 0,
    bassLevels: new Array(BASS_STEPS).fill(0), bassNext: 0, bassCount: 0,
    lo: [], hi: [], prev: null,
    kick: newOnset(0, 0.3, 2.0, 0.05, 6), snare: newOnset(0.3, 0.6, 2.0, 0.04, 5), hat: newOnset(0.6, 1, 1.8, 0.025, 4),
    koi: [], swirls: [], pixels: null
  }
}

function newKoi(offset, phase) {
  return {
    joints: [], prevJoints: [], offset: offset, phase: phase, phaseStep: 0, stroke: 0.6,
    flick: 0, flickRest: 0, flickPower: 0, flickDir: 1, sprite: null
  }
}

function newGrid(width, height) {
  return { w: width | 0, h: height | 0, lap: 0, px: new Int8Array(width * height) }
}

function copyPoints(points) {
  return points.map(function (p) { return { x: p.x, y: p.y } })
}

function shifted(koi, dx, dy) {
  return Object.assign({}, koi, { joints: koi.joints.map(function (p) { return { x: p.x + dx, y: p.y + dy } }) })
}

function lowerBound(sorted, value) {
  var lo = 0, hi = sorted.length
  while (lo < hi) {
    var mid = (lo + hi) >> 1
    if (sorted[mid] < value) lo = mid + 1
    else hi = mid
  }
  return lo
}

function toAngle(yy, dist) {
  return dist * yy.size * 2 * Math.PI / yy.trackLen
}

function layout(yy, width, height) {
  yy.w = width
  yy.h = height
  yy.cx = width / 2
  yy.cy = height / 2
  yy.strip = width > height * 3
  if (yy.strip) {
    yy.size = Math.min(height * 0.84 / (2 * HALF_BODY), width / 80)
    yy.radius = Math.min(height * 0.3, yy.size * 4.5)
    var hidden = SEG * (JOINTS - 1) + NOSE + TAIL_FIN
    yy.lap = Math.round(width + hidden * yy.size)
    yy.waves = Math.max(1, Math.round(yy.lap / (55 * yy.size)))
    yy.pad = 0
    var wave = yy.lap / yy.waves
    yy.waveArc = [0]
    for (var i = 1; i <= ARC_STEPS; i++) {
      var x0 = (i - 1) * wave / ARC_STEPS, x1 = i * wave / ARC_STEPS
      var dy = (Math.cos(2 * Math.PI * x1 / wave) - Math.cos(2 * Math.PI * x0 / wave)) * yy.radius
      yy.waveArc.push(yy.waveArc[i - 1] + Math.hypot(x1 - x0, dy))
    }
    yy.trackLen = yy.waves * yy.waveArc[ARC_STEPS]
  } else {
    var m = Math.min(width, height, 160)
    yy.radius = m * 0.36
    yy.lap = 2 * Math.PI * yy.radius
    yy.trackLen = yy.lap
    yy.pad = m * 0.17
    yy.size = Math.min(m * 0.34 * 1.35 / 18, (width / 2 - yy.radius) / HALF_BODY, (height / 2 - yy.radius) / HALF_BODY)
  }
  yy.koi = [newKoi(0, 0), newKoi(Math.PI, 1.5)]
  if (yy.strip) {
    yy.koi[0].offset = -toAngle(yy, GAP)
    yy.koi[1].offset = 0
  }
  yy.koi.forEach(function (koi) {
    lineUp(yy, koi)
    koi.prevJoints = copyPoints(koi.joints)
  })
  yy.swirls = []
  yy.pixels = new Int8Array(width * height)
}

function lineUp(yy, koi) {
  var a = yy.angle + koi.offset
  for (var j = 0; j < JOINTS; j++) {
    koi.joints[j] = trackPoint(yy, a)
    a -= toAngle(yy, SEG)
  }
  follow(yy.size, koi)
}

function trackPoint(yy, a) {
  if (!yy.strip) return { x: yy.cx + Math.cos(a) * yy.radius, y: yy.cy + Math.sin(a) * yy.radius }
  var per = yy.waveArc[ARC_STEPS]
  var s = a / (2 * Math.PI) * yy.trackLen
  var lapIndex = Math.floor(s / per)
  s -= lapIndex * per
  var i = Math.max(1, Math.min(ARC_STEPS, lowerBound(yy.waveArc, s)))
  var t = (s - yy.waveArc[i - 1]) / (yy.waveArc[i] - yy.waveArc[i - 1])
  var wave = yy.lap / yy.waves
  var x = (i - 1 + t) * wave / ARC_STEPS
  return { x: lapIndex * wave + x + yy.w * 0.6, y: yy.cy + Math.cos(2 * Math.PI * x / wave) * yy.radius }
}

function follow(size, koi) {
  var seg = SEG * size
  for (var j = 1; j < JOINTS; j++) {
    var a = koi.joints[j - 1], b = koi.joints[j]
    var dx = b.x - a.x, dy = b.y - a.y, dist = Math.hypot(dx, dy)
    if (dist > 0) {
      b.x = a.x + dx / dist * seg
      b.y = a.y + dy / dist * seg
    }
  }
}

function flickTail(koi, power) {
  if (koi.flick === 0) {
    koi.flickPower = power
    koi.flickDir = -koi.flickDir
  }
  koi.flick = Math.max(koi.flick, FLICK_STEPS - koi.flick)
}

function tailBend(koi) {
  var wave = Math.sin(Math.PI * koi.flick / FLICK_STEPS)
  return 0.6 * wave * wave * koi.flickPower
}

function onsetStep(onset, bands, prev) {
  var n = bands.length, flux = 0
  for (var i = Math.floor(onset.from * n); i < Math.floor(onset.to * n) && i < prev.length; i++)
    flux += Math.max(0, bands[i] - prev[i])
  var threshold = Math.max(onset.mean + onset.k * onset.dev, onset.floor)
  var hit = flux > threshold && onset.since >= onset.gap
  onset.mean = onset.mean * 0.92 + flux * 0.08
  onset.dev = onset.dev * 0.92 + Math.abs(flux - onset.mean) * 0.08
  onset.since = hit ? 0 : onset.since + 1
  return { hit: hit, strength: flux / threshold }
}

function advance(yy, bands, playing) {
  var n = bands.length
  if (yy.lo.length !== n) {
    yy.lo = new Array(n).fill(1)
    yy.hi = new Array(n).fill(0)
    yy.prev = null
  }
  var energy = 0, avg = 0
  for (var i = 0; i < n; i++) {
    var b = bands[i]
    energy += b
    yy.hi[i] = Math.max(b, yy.hi[i] - 0.004)
    yy.lo[i] = Math.min(b, yy.lo[i] + 0.004)
    avg += Math.min(1, Math.max(0, (b - yy.lo[i]) / Math.max(yy.hi[i] - yy.lo[i], 0.12)))
  }
  if (n > 0) {
    energy /= n
    avg /= n
  }
  var quiet = !playing || energy < QUIET
  if (playing) {
    yy.loud += (avg - yy.loud) * 0.05
    yy.mood += (avg - yy.mood) * 0.01
    var bloom = quiet ? 0 : Math.min(1, Math.max(0, (yy.mood - 0.1) / 0.5))
    yy.bloom += (bloom - yy.bloom) * 0.02
  }

  if (yy.prev) {
    var drums = [{ onset: yy.kick, koi: 0, here: yy.strip }, { onset: yy.snare, koi: 0, here: !yy.strip },
                 { onset: yy.hat, koi: 1, here: true }]
    drums.forEach(function (drum) {
      var onset = onsetStep(drum.onset, bands, yy.prev)
      var koi = yy.koi[drum.koi]
      if (onset.hit && drum.here && !quiet && onset.strength >= STANDOUT && koi.flickRest === 0) {
        flickTail(koi, Math.min(MAX_POWER, 0.6 + 0.3 * onset.strength))
        koi.flickRest = REST
      }
    })
  }
  yy.prev = bands.slice()

  yy.breath *= 0.8
  if (playing && n > 0) {
    var low = Math.max(1, Math.floor(n / 5)), level = 0
    for (var l = 0; l < low; l++) level += bands[l] / low
    yy.bassLevels[yy.bassNext] = level
    yy.bassNext = (yy.bassNext + 1) % BASS_STEPS
    yy.bassCount = Math.min(yy.bassCount + 1, BASS_STEPS)
    if (!quiet && !yy.strip) {
      var bassLow = level, bassHigh = level
      for (var past = 0; past < yy.bassCount; past++) {
        bassLow = Math.min(bassLow, yy.bassLevels[past])
        bassHigh = Math.max(bassHigh, yy.bassLevels[past])
      }
      yy.breath = (level - bassLow) / Math.max(bassHigh - bassLow, 0.08)
    }
  }

  if (playing) {
    var pace = quiet ? 0.066 : yy.strip ? 0.11 + 0.22 * yy.loud : 0.09 + 0.13 * yy.mood
    if (yy.strip) pace = Math.max(pace * STRIP_PACE, (quiet ? 0.7 : 1.0 + 1.0 * yy.loud) / yy.size)
    yy.angle += toAngle(yy, pace)
  }
  var stroke = quiet ? 0.1 : 0.3 + yy.mood, beat = quiet ? 0.09 : 0.125 + 0.085 * yy.mood
  yy.koi.forEach(function (koi) {
    koi.prevJoints = copyPoints(koi.joints)
    koi.phaseStep = 0
    koi.flickRest = Math.max(0, koi.flickRest - 1)
    koi.stroke += (stroke - koi.stroke) * 0.02
    if (playing) {
      koi.phaseStep = beat
      koi.phase += beat
      koi.joints[0] = trackPoint(yy, yy.angle + koi.offset)
      follow(yy.size, koi)
    }
    if (koi.flick === FLICK_STEPS && !yy.strip) {
      var tail = koi.joints[JOINTS - 1], root = koi.joints[JOINTS - 2]
      var out = Math.atan2(tail.y - root.y, tail.x - root.x) + koi.flickDir * Math.PI / 2
      yy.swirls.push({ x: tail.x + Math.cos(out) * 1.2 * yy.size, y: tail.y + Math.sin(out) * 1.2 * yy.size,
                       angle: out, spin: koi.flickDir, life: SWIRL_LIFE })
    }
    if (koi.flick > 0) koi.flick--
  })
  yy.swirls = yy.swirls.filter(function (swirl) { return --swirl.life > 0 })
}

function set(grid, x, y, tag) {
  if (grid.lap) x = ((x % grid.lap) + grid.lap) % grid.lap
  if (tag < 0 || x < 0 || y < 0 || x >= grid.w || y >= grid.h) return
  grid.px[(y * grid.w + x) | 0] = tag
}

function plot(grid, x, y, tag) {
  set(grid, Math.floor(x), Math.floor(y), tag)
}

function disc(grid, cx, cy, r, shade) {
  if (r <= 0) return
  for (var y = Math.max(0, Math.floor(cy - r)); y <= Math.min(grid.h - 1, Math.ceil(cy + r)); y++) {
    for (var x = Math.max(0, Math.floor(cx - r)); x <= Math.min(grid.w - 1, Math.ceil(cx + r)); x++) {
      var dx = (x + 0.5 - cx) / r, dy = (y + 0.5 - cy) / r
      if (dx * dx + dy * dy <= 1) set(grid, x, y, shade(dx, dy))
    }
  }
}

function fill(grid, cx, cy, r, tag) {
  if (r <= 0) return
  for (var y = Math.max(0, Math.floor(cy - r)); y <= Math.min(grid.h - 1, Math.ceil(cy + r)); y++) {
    var dy = (y + 0.5 - cy) / r
    if (dy * dy > 1) continue
    var half = Math.sqrt(1 - dy * dy) * r
    var from = Math.max(0, Math.floor(cx - r), Math.ceil(cx - half - 0.5))
    var to = Math.min(grid.w - 1, Math.ceil(cx + r), Math.floor(cx + half - 0.5))
    if (from <= to) grid.px.fill(tag, y * grid.w + from, y * grid.w + to + 1)
  }
}

function opaquePixels(grid) {
  var px = grid.px, water = WATER, opaque = []
  for (var i = 0; i < px.length; i++) if (px[i] !== water) opaque.push(i)
  return opaque
}

function stamp(target, grid, opaque, x, y) {
  for (var o = 0; o < opaque.length; o++)
    set(target, x + opaque[o] % grid.w, y + Math.floor(opaque[o] / grid.w), grid.px[opaque[o]])
}

function drawSwirl(grid, size, swirl) {
  var open = (SWIRL_LIFE - swirl.life) / SWIRL_LIFE
  var r = (1 + 2.5 * open) * size
  for (var i = 0; i <= SWIRL_POINTS; i++) {
    var t = i / SWIRL_POINTS
    if (t >= 1 - open * 0.6) break
    var a = swirl.angle + t * 4.5 * swirl.spin, rr = r * (0.4 + 0.6 * t)
    plot(grid, swirl.x + Math.cos(a) * rr, swirl.y + Math.sin(a) * rr, DIM)
  }
}

function drawKoi(yy, grid, koi, pat) {
  if (yy.strip) {
    var headX = Math.floor(koi.joints[0].x), headY = Math.floor(koi.joints[0].y)
    var sprite = koi.sprite
    if (!sprite || headX !== sprite.hx || headY !== sprite.hy || koi.flick > 0 || sprite.flicked)
      sprite = koi.sprite = drawSprite(yy.size, koi, pat)
    stamp(grid, sprite.grid, sprite.opaque, sprite.x, sprite.y)
    return
  }
  var reach = Math.ceil(HALF_BODY * yy.size) + 2
  var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
  koi.joints.forEach(function (p) {
    x0 = Math.min(x0, p.x); x1 = Math.max(x1, p.x)
    y0 = Math.min(y0, p.y); y1 = Math.max(y1, p.y)
  })
  var ox = Math.floor(x0) - reach, oy = Math.floor(y0) - reach
  var alone = newGrid(Math.ceil(x1) + reach - ox + 1, Math.ceil(y1) + reach - oy + 1)
  drawShape(alone, yy.size, shifted(koi, -ox, -oy), pat, true)
  closeGaps(alone.px, alone.w, pat.body)
  stamp(grid, alone, opaquePixels(alone), ox, oy)
  var j = koi.joints
  var head = Math.atan2(j[0].y - j[2].y, j[0].x - j[2].x)
  var eye = RADII[0] * yy.size * 0.75
  for (var side = -1; side <= 1; side += 2)
    plot(grid, j[0].x + Math.cos(head + side * 1.1) * eye, j[0].y + Math.sin(head + side * 1.1) * eye, WATER)
}

function drawSprite(size, koi, pat) {
  var head = koi.joints[0]
  var hx = Math.floor(head.x), hy = Math.floor(head.y)
  var sx = hx + 0.5 - head.x, sy = hy + 0.5 - head.y
  var reach = Math.ceil(HALF_BODY * size) + 1
  var x0 = hx, y0 = hy, x1 = hx, y1 = hy
  koi.joints.forEach(function (p) {
    x0 = Math.min(x0, Math.floor(p.x + sx)); x1 = Math.max(x1, Math.floor(p.x + sx))
    y0 = Math.min(y0, Math.floor(p.y + sy)); y1 = Math.max(y1, Math.floor(p.y + sy))
  })
  var ox = x0 - reach, oy = y0 - reach
  var grid = newGrid(x1 - x0 + 2 * reach + 1, y1 - y0 + 2 * reach + 1)
  drawShape(grid, size, shifted(koi, sx - ox, sy - oy), pat, false)
  closeGaps(grid.px, grid.w, pat.body)
  addStripEyes(grid.px, grid.w, hx - ox, hy - oy, pat.body)
  return { grid: grid, opaque: opaquePixels(grid), hx: hx, hy: hy, x: ox, y: oy, flicked: koi.flick > 0 }
}

function closeGaps(px, width, body) {
  var h = (px.length / width) | 0, water = WATER
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < width; x++) {
      var i = y * width + x
      if (px[i] === water && ((x > 0 && x < width - 1 && px[i - 1] !== water && px[i + 1] !== water)
          || (y > 0 && y < h - 1 && px[i - width] !== water && px[i + width] !== water)))
        px[i] = body
    }
  }
}

function addStripEyes(px, width, hx, hy, body) {
  var h = (px.length / width) | 0, ex = hx + 1
  for (var e = hy; e > 1; e--) {
    if (ex < width && hy + e < h && px[(hy - e) * width + ex] === body && px[(hy + e) * width + ex] === body) {
      px[(hy - e + 1) * width + ex] = WATER
      px[(hy + e - 1) * width + ex] = WATER
      return
    }
  }
}

function drawShape(grid, size, koi, pat, swim) {
  var j = copyPoints(koi.joints)
  var wag = 0.5
  if (swim) {
    wag = 0.6 * koi.stroke
    for (var i = 4; i < JOINTS; i++) {
      var a = koi.joints[i - 1], b = koi.joints[i]
      var dx = a.x - b.x, dy = a.y - b.y, dist = Math.hypot(dx, dy)
      if (dist > 0) {
        var f = (i - 3) / (JOINTS - 4)
        var off = Math.sin(koi.phase - f * 2.5) * f * f * koi.stroke * 1.8 * size
        j[i].x -= dy / dist * off
        j[i].y += dx / dist * off
      }
    }
  }
  if (koi.flick > 0) {
    var bend = tailBend(koi) * koi.flickDir
    var hx = j[JOINTS - 5].x - j[JOINTS - 6].x, hy = j[JOINTS - 5].y - j[JOINTS - 6].y, len = Math.hypot(hx, hy)
    if (len > 0) {
      for (var t = JOINTS - 5; t < JOINTS; t++) {
        var push = (t - (JOINTS - 6)) / 5 * bend * size * 1.5
        j[t].x += -hy / len * push
        j[t].y += hx / len * push
      }
    }
  }

  var head = Math.atan2(j[0].y - j[2].y, j[0].x - j[2].x)
  var flap = Math.sin(koi.phase * 0.5) * 0.25
  for (var side = -1; side <= 1; side += 2) {
    var fin = head + Math.PI + side * (1.25 + flap)
    for (var lobe = 0; lobe < 3; lobe++) {
      var reach = (RADII[2] + 0.6 + lobe) * size
      fill(grid, j[2].x + Math.cos(fin) * reach, j[2].y + Math.sin(fin) * reach, (1.5 - lobe * 0.35) * size, pat.body)
    }
  }
  var back = Math.atan2(j[7].y - j[6].y, j[7].x - j[6].x)
  for (var s = -1; s <= 1; s += 2) {
    var dorsal = back + s * 1.9
    fill(grid, j[7].x + Math.cos(dorsal) * 1.6 * size, j[7].y + Math.sin(dorsal) * 1.6 * size, 0.8 * size, pat.body)
  }
  var last = j[JOINTS - 1], before = j[JOINTS - 2]
  var tail = Math.atan2(last.y - before.y, last.x - before.x) + Math.sin(koi.phase - 2) * wag
  fill(grid, last.x + Math.cos(tail) * 1.2 * size, last.y + Math.sin(tail) * 1.2 * size, 0.75 * size, pat.body)
  fill(grid, last.x + Math.cos(tail) * 0.6 * size, last.y + Math.sin(tail) * 0.6 * size, 0.65 * size, pat.body)

  for (var k = JOINTS - 1; k >= 0; k--) {
    fill(grid, j[k].x, j[k].y, RADII[k] * size, pat.body)
    if (k > 0) fill(grid, (j[k].x + j[k - 1].x) / 2, (j[k].y + j[k - 1].y) / 2, (RADII[k] + RADII[k - 1]) / 2 * size, pat.body)
  }
  for (var p = JOINTS - 1; p >= 0; p--)
    if (pat.back[p] !== WATER) fill(grid, j[p].x, j[p].y, RADII[p] * size * 0.62, pat.back[p])
}

function petalWidth(along) {
  var f = along * PETAL_SAMPLES, i = Math.floor(f)
  return PETAL_WIDTHS[i] + (PETAL_WIDTHS[i + 1] - PETAL_WIDTHS[i]) * (f - i)
}

function padShade(dx, dy) {
  var ahead = dx * NOTCH_X + dy * NOTCH_Y, aside = dx * NOTCH_Y - dy * NOTCH_X
  return ahead > 0 && Math.abs(aside) < NOTCH_SLOPE * ahead && dx * dx + dy * dy > NOTCH_INNER * NOTCH_INNER ? -1 : PAD
}

function drawLotus(yy, grid) {
  var outer = 0.5 + 0.12 * yy.bloom + 0.2 * yy.breath, inner = 0.3 + 0.08 * yy.bloom + 0.08 * yy.breath
  var rings = [{ length: yy.pad * outer, turn: 0, tag: INK }, { length: yy.pad * inner, turn: Math.PI / PETALS, tag: RED }]
  rings.forEach(function (ring) {
    disc(grid, yy.cx, yy.cy, ring.length, function (dx, dy) {
      var a = Math.atan2(dy, dx) - ring.turn
      a -= Math.round(a / (2 * Math.PI / PETALS)) * 2 * Math.PI / PETALS
      var r = Math.hypot(dx, dy), along = r * Math.cos(a), across = r * Math.sin(a)
      return along > 0 && along < 1 && Math.abs(across) <= petalWidth(along) ? ring.tag : -1
    })
  })
  fill(grid, yy.cx, yy.cy, yy.pad * inner * 0.35, GOLD)
}

function draw(yy) {
  var grid = { w: yy.w, h: yy.h, lap: yy.strip ? yy.lap : 0, px: yy.pixels }
  grid.px.fill(WATER)
  yy.swirls.forEach(function (swirl) { drawSwirl(grid, yy.size, swirl) })
  var ahead = VisualizerHelpers.cliampTickFraction(yy.clock)
  yy.koi.forEach(function (koi, index) {
    var shown = Object.assign({}, koi, {
      joints: koi.joints.map(function (p, j) {
        return { x: p.x + (p.x - koi.prevJoints[j].x) * ahead, y: p.y + (p.y - koi.prevJoints[j].y) * ahead }
      }),
      phase: koi.phase + koi.phaseStep * ahead
    })
    drawKoi(yy, grid, shown, PATTERNS[index])
    koi.sprite = shown.sprite
  })
  disc(grid, yy.cx, yy.cy, yy.pad, padShade)
  drawLotus(yy, grid)
}

function tagColors(d) {
  var tiers = VisualizerHelpers.specTiers(d)
  return [null, VisualizerHelpers.rgba(d.dim, 1), tiers[0], tiers[2], VisualizerHelpers.rgba(d.foreground, 1), tiers[1]]
}

function render(canvas, frameData) {
  var w = Math.floor(frameData.width), h = Math.floor(frameData.height)
  if (w <= 0 || h <= 0) return

  var animationState = frameData.state
  if (!animationState.yinYang) animationState.yinYang = newDriver()
  var yy = animationState.yinYang
  if (w !== yy.w || h !== yy.h) layout(yy, w, h)
  var ticks = VisualizerHelpers.cliampTicks(yy.clock)
  var bands = VisualizerHelpers.cliampBands(frameData.bands, frameData.bandEdges)
  for (var tick = 0; tick < ticks; tick++) advance(yy, bands, frameData.playing)
  draw(yy)
  VisualizerHelpers.paintTagGrid(canvas, yy.pixels, w, h, tagColors(frameData))
}

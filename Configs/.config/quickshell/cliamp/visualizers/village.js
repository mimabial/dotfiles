// Clair de Lune — a compact illustrated nightscape whose stars, windows and
// chapel glow respond to the music without bending the architecture.
.pragma library
.import "helpers.js" as H

var TAU = Math.PI * 2

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, Number(value) || 0))
}

function nightInk(d, alpha, tint) {
  var foreground = H.colorRgb(d.foreground)
  var light = clamp((Math.max(foreground.r, foreground.g, foreground.b)
                    + Math.min(foreground.r, foreground.g, foreground.b)) / 510, 0.14, 0.88)
  var moonlight = H.hueShift("#8dbbc7", 0, 0.26, light)
  return H.mixColor(d.foreground, moonlight, tint === undefined ? 0.20 : tint, alpha)
}

function smoothLevel(current, target, dt, attack, release) {
  var tau = target > current ? attack : release
  return current + (target - current) * (1 - Math.exp(-dt / tau))
}

function groundY(s, x) {
  return s.base + Math.sin(x / s.w * 7.1 + 0.5) * s.scale
    + Math.sin(x / s.w * 2.4 + 1.8) * s.scale * 0.65
}

function addWindow(s, x, y, width, height, depth) {
  s.windows.push({
    x: Math.round(x), y: Math.round(y), width: width, height: height,
    threshold: 0.08 + H.lcgRand01(s.rng) * 0.22,
    band: s.windows.length,
    depth: depth === undefined ? 1 : depth,
    value: 0
  })
}

function addHouse(s, left, right, wallHeight, roofHeight, windowCount, chimneySide, depth, setback) {
  var x0 = s.w * left, x1 = s.w * right
  var layer = clamp(depth, 0.45, 1)
  var base = groundY(s, (x0 + x1) / 2) - (setback || 0) * s.scale
  var house = {
    x0: x0, x1: x1, base: base,
    eave: base - wallHeight * s.scale,
    ridgeX: x0 + (x1 - x0) * (0.46 + H.lcgRand01(s.rng) * 0.08),
    roofHeight: roofHeight * s.scale,
    chimneySide: chimneySide,
    depth: layer
  }
  if (chimneySide !== 0) {
    var roofRun = chimneySide < 0 ? house.ridgeX - x0 : x1 - house.ridgeX
    house.chimneyX = chimneySide < 0 ? x0 + roofRun * 0.46 : house.ridgeX + roofRun * 0.54
    house.chimneyY = house.eave - house.roofHeight * 0.52
    s.chimneys.push({ x: house.chimneyX, y: house.chimneyY - 4 * s.scale, depth: layer })
  }

  var doorWidth = Math.max(4, 5 * s.scale)
  house.door = {
    x: house.ridgeX - doorWidth / 2,
    y: base - 7 * s.scale,
    width: doorWidth,
    height: 7 * s.scale
  }
  var usableLeft = x0 + 5 * s.scale
  var usableRight = x1 - 5 * s.scale
  for (var i = 0; i < windowCount; i++) {
    var windowX = usableLeft + (usableRight - usableLeft) * (i + 0.5) / windowCount
    if (Math.abs(windowX - house.ridgeX) < doorWidth) windowX += i % 2 ? doorWidth : -doorWidth
    addWindow(s, windowX - 1.5, house.eave + 3 * s.scale, 3, 3, layer)
  }
  s.houses.push(house)
}

function addPine(s, xFraction, height, width, depth, setback) {
  var x = s.w * xFraction
  s.pines.push({
    x: x, base: groundY(s, x) - (setback || 0) * s.scale,
    height: height * s.scale, width: width * s.scale,
    depth: clamp(depth, 0.45, 1)
  })
}

function build(s, w, h, frame) {
  s.w = w
  s.h = h
  s.scale = clamp(h / 46, 0.72, 1.18)
  s.base = Math.round(h * 0.83)
  s.rng = { v: 0x51A7C3 }
  s.houses = []
  s.pines = []
  s.windows = []
  s.chimneys = []

  addHouse(s, 0.045, 0.165, 8, 5, 2, -1, 0.62, 2)
  addPine(s, 0.205, 16, 11, 0.72, 1)
  addHouse(s, 0.235, 0.370, 12, 9, 2, 1, 0.96, 0)
  addHouse(s, 0.600, 0.715, 10, 8, 2, -1, 0.88, 0)
  addHouse(s, 0.755, 0.835, 7, 5, 1, 1, 0.54, 3)
  addPine(s, 0.895, 20, 13, 0.82, 0)
  addPine(s, 0.965, 14, 10, 0.56, 2)

  var churchX0 = w * 0.405, churchX1 = w * 0.565
  var churchBase = groundY(s, (churchX0 + churchX1) / 2)
  var towerX0 = w * 0.500, towerX1 = churchX1
  s.church = {
    x0: churchX0, x1: churchX1, base: churchBase,
    naveRight: towerX0, naveEave: churchBase - 11 * s.scale,
    towerX0: towerX0, towerX1: towerX1,
    towerTop: churchBase - 22 * s.scale,
    spireX: (towerX0 + towerX1) / 2,
    spireTop: Math.max(4 * s.scale, churchBase - 33 * s.scale)
  }
  addWindow(s, churchX0 + (towerX0 - churchX0) * 0.27,
            s.church.naveEave + 3 * s.scale, 3, 3, 1)
  addWindow(s, churchX0 + (towerX0 - churchX0) * 0.67,
            s.church.naveEave + 3 * s.scale, 3, 3, 1)

  s.moon = {
    x: Math.round(w * 0.825),
    y: Math.round(h * 0.19),
    radius: Math.max(5.5, h * 0.13)
  }
  var starCount = Math.max(16, Math.min(28, Math.round(w / 15)))
  s.stars = []
  var attempts = 0
  while (s.stars.length < starCount && attempts++ < starCount * 5) {
    var starX = Math.round(3 + H.lcgRand01(s.rng) * (w - 6))
    var starY = Math.round(2 + H.lcgRand01(s.rng) * h * 0.48)
    var moonDx = (starX - s.moon.x) / (s.moon.radius + 16 * s.scale)
    var moonDy = (starY - s.moon.y) / (s.moon.radius + 7 * s.scale)
    if (moonDx * moonDx + moonDy * moonDy < 1) continue
    s.stars.push({
      x: starX,
      y: starY,
      alpha: 0.22 + H.lcgRand01(s.rng) * 0.44,
      phase: H.lcgRand01(s.rng) * TAU,
      speed: 0.70 + H.lcgRand01(s.rng) * 1.50,
      strength: 0.35 + H.lcgRand01(s.rng) * 0.65,
      cross: H.lcgRand01(s.rng) > 0.80
    })
  }

  s.frame = Number(frame) || 0
  s.clock = 0
  s.prevBeat = 0
  s.meteor = null
  s.meteorSparks = []
  s.meteorSequence = 0
  s.lastMeteor = -12
  s.bass = 0
  s.mid = 0
  s.treble = 0
}

function onEnter(state) {
  state.village = null
}

function strokePath(ctx, points) {
  if (!points || points.length < 2) return
  ctx.beginPath()
  ctx.moveTo(points[0][0], points[0][1])
  for (var i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1])
  ctx.stroke()
}

function settleBackground(ctx, d, s) {
  // The nebula is shared by every visualizer. A surface-coloured veil lets its motion
  // remain in the sky while restoring enough quiet contrast for fine architectural ink.
  var veil = ctx.createLinearGradient(0, 0, 0, s.h)
  veil.addColorStop(0, H.rgba(d.surface, 0.34))
  veil.addColorStop(0.55, H.rgba(d.surface, 0.58))
  veil.addColorStop(1, H.rgba(d.surface, 0.82))
  ctx.fillStyle = veil
  ctx.fillRect(0, 0, s.w, s.h)

  var quietRadius = s.moon.radius + 18 * s.scale
  var quiet = ctx.createRadialGradient(s.moon.x, s.moon.y, s.moon.radius,
                                       s.moon.x, s.moon.y, quietRadius)
  quiet.addColorStop(0, H.rgba(d.surface, 0.62))
  quiet.addColorStop(0.58, H.rgba(d.surface, 0.30))
  quiet.addColorStop(1, H.rgba(d.surface, 0))
  ctx.fillStyle = quiet
  ctx.fillRect(s.moon.x - quietRadius, s.moon.y - quietRadius,
               quietRadius * 2, quietRadius * 2)
}

function drawSky(ctx, d, s, treble) {
  for (var i = 0; i < s.stars.length; i++) {
    var star = s.stars[i]
    var twinkle = 0.5 + 0.5 * Math.sin(s.clock * star.speed + star.phase)
    var alpha = clamp(star.alpha * (0.24 + twinkle * 0.76)
                      + treble * (0.05 + twinkle * 0.20), 0.04, 0.86)
    ctx.fillStyle = nightInk(d, alpha, 0.12)
    ctx.fillRect(star.x, star.y, 1, 1)
    if (star.cross && alpha > 0.46) {
      var strength = isFinite(Number(star.strength)) ? Number(star.strength) : 0.5
      var flare = 0.8 + strength + twinkle * (0.45 + strength * 0.55) + treble * 0.45
      ctx.strokeStyle = nightInk(d, alpha * 0.72, 0.30)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(star.x - flare, star.y); ctx.lineTo(star.x + flare, star.y)
      ctx.moveTo(star.x, star.y - flare); ctx.lineTo(star.x, star.y + flare)
      ctx.stroke()
      ctx.fillStyle = H.mixColor(d.accent, d.foreground, 0.45, alpha)
      ctx.beginPath(); ctx.arc(star.x, star.y, 0.55 + strength * 0.45, 0, TAU); ctx.fill()
    }
  }

  var moonX = s.moon.x, moonY = s.moon.y, moonR = s.moon.radius
  ctx.strokeStyle = nightInk(d, 0.07 + treble * 0.04, 0.45)
  ctx.lineWidth = 1
  ctx.beginPath(); ctx.arc(moonX, moonY, moonR + 4 * s.scale, 0, TAU); ctx.stroke()
  ctx.strokeStyle = nightInk(d, 0.12 + treble * 0.06, 0.40)
  ctx.beginPath(); ctx.arc(moonX, moonY, moonR + 2 * s.scale, 0, TAU); ctx.stroke()

  ctx.strokeStyle = nightInk(d, 0.36 + treble * 0.08, 0.38)
  ctx.beginPath(); ctx.arc(moonX, moonY, moonR, 0, TAU); ctx.stroke()

  // The illuminated half faces the chapel, with a straight terminator and full rim.
  ctx.fillStyle = nightInk(d, 0.34 + treble * 0.12, 0.38)
  ctx.strokeStyle = nightInk(d, 0.86 + treble * 0.10, 0.32)
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.moveTo(moonX, moonY + moonR)
  ctx.arc(moonX, moonY, moonR, Math.PI / 2, Math.PI * 1.5, false)
  ctx.closePath()
  ctx.fill()
  ctx.stroke()
}

function drawHills(ctx, d, s, mid) {
  ctx.lineWidth = 1
  ctx.strokeStyle = nightInk(d, 0.12 + mid * 0.05, 0.38)
  ctx.beginPath()
  ctx.moveTo(0, s.base - 4 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.12, s.base - 16 * s.scale,
                       s.w * 0.27, s.base - 5 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.42, s.base - 14 * s.scale,
                       s.w * 0.58, s.base - 4 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.76, s.base - 13 * s.scale,
                       s.w, s.base - 5 * s.scale)
  ctx.stroke()

  ctx.strokeStyle = nightInk(d, 0.08 + mid * 0.05, 0.52)
  ctx.beginPath()
  ctx.moveTo(0, s.base - 1 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.20, s.base - 9 * s.scale,
                       s.w * 0.39, s.base - 2 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.61, s.base - 10 * s.scale,
                       s.w, s.base - 1 * s.scale)
  ctx.stroke()
}

function drawMoonPath(ctx, d, s, treble) {
  var c = s.church
  var topX = c.spireX
  var bottomCenter = s.w * 0.48
  var bottomHalf = 24 * s.scale
  ctx.fillStyle = nightInk(d, 0.045 + treble * 0.035, 0.48)
  ctx.strokeStyle = nightInk(d, 0.16 + treble * 0.08, 0.42)
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.moveTo(topX - 1, c.base)
  ctx.bezierCurveTo(topX - 4, c.base + 3 * s.scale,
                    bottomCenter - bottomHalf * 0.20, s.h - 4 * s.scale,
                    bottomCenter - bottomHalf, s.h + 1)
  ctx.lineTo(bottomCenter + bottomHalf, s.h + 1)
  ctx.bezierCurveTo(bottomCenter + bottomHalf * 0.18, s.h - 4 * s.scale,
                    topX + 4, c.base + 3 * s.scale,
                    topX + 1, c.base)
  ctx.closePath()
  ctx.fill()
  ctx.stroke()

  for (var i = 1; i <= 3; i++) {
    var t = i / 4
    var y = c.base + (s.h - c.base) * t
    var center = topX + (bottomCenter - topX) * t
    var shimmer = Math.sin(s.clock * 0.42 + i * 1.7) * treble * 1.8
    var half = 1.5 + bottomHalf * t * 0.55
    ctx.strokeStyle = nightInk(d, 0.12 + treble * 0.13, 0.48)
    ctx.beginPath()
    ctx.moveTo(center - half + shimmer, y)
    ctx.lineTo(center + half * 0.72 + shimmer, y)
    ctx.stroke()
  }
}

function drawHouse(ctx, d, s, house) {
  var eave = house.eave
  ctx.strokeStyle = nightInk(d, 0.48 + house.depth * 0.40, 0.20)
  ctx.lineWidth = 0.72 + house.depth * 0.44
  ctx.lineJoin = "round"
  ctx.lineCap = "round"

  var outline = [
    [house.x0, house.base], [house.x0, eave], [house.x0 - 2 * s.scale, eave],
    [house.ridgeX, eave - house.roofHeight],
    [house.x1 + 2 * s.scale, eave], [house.x1, eave], [house.x1, house.base]
  ]
  strokePath(ctx, outline)

  if (house.chimneySide !== 0) {
    var chimneyWidth = 3.5 * s.scale
    var cx = house.chimneyX
    strokePath(ctx, [
      [cx - chimneyWidth / 2, house.chimneyY + 2 * s.scale],
      [cx - chimneyWidth / 2, house.chimneyY - 4 * s.scale],
      [cx + chimneyWidth / 2, house.chimneyY - 4 * s.scale],
      [cx + chimneyWidth / 2, house.chimneyY]
    ])
  }

  ctx.strokeStyle = nightInk(d, 0.25 + house.depth * 0.30, 0.26)
  ctx.lineWidth = 1
  ctx.strokeRect(house.door.x, house.door.y, house.door.width, house.door.height)
  ctx.fillStyle = nightInk(d, 0.24 + house.depth * 0.28, 0.18)
  ctx.fillRect(house.door.x + house.door.width - 1.5, house.door.y + house.door.height * 0.52, 1, 1)

  if (house.x1 - house.x0 > 45 * s.scale) {
    ctx.strokeStyle = nightInk(d, 0.16 + house.depth * 0.18, 0.30)
    strokePath(ctx, [
      [house.x0 + 4 * s.scale, eave - 0.5],
      [house.ridgeX, eave - house.roofHeight + 2.5 * s.scale],
      [house.x1 - 4 * s.scale, eave - 0.5]
    ])
  }
}

function drawChurch(ctx, d, s, bass) {
  var c = s.church
  var ink = nightInk(d, 0.94, 0.22)
  ctx.strokeStyle = ink
  ctx.lineWidth = 1.2
  ctx.lineJoin = "round"
  ctx.lineCap = "round"

  var naveRidgeX = c.x0 + (c.naveRight - c.x0) * 0.48
  strokePath(ctx, [
    [c.x0, c.base], [c.x0, c.naveEave], [c.x0 - 2 * s.scale, c.naveEave],
    [naveRidgeX, c.naveEave - 7 * s.scale],
    [c.naveRight + 1.5 * s.scale, c.naveEave],
    [c.naveRight, c.naveEave], [c.naveRight, c.towerTop],
    [c.towerX0 - 1.5 * s.scale, c.towerTop],
    [c.spireX, c.spireTop],
    [c.towerX1 + 1.5 * s.scale, c.towerTop],
    [c.towerX1, c.towerTop], [c.towerX1, c.base]
  ])

  var crossTop = Math.max(1, c.spireTop - 4 * s.scale)
  ctx.beginPath()
  ctx.moveTo(c.spireX, c.spireTop + 1)
  ctx.lineTo(c.spireX, crossTop)
  ctx.moveTo(c.spireX - 2.5 * s.scale, crossTop + 1.5 * s.scale)
  ctx.lineTo(c.spireX + 2.5 * s.scale, crossTop + 1.5 * s.scale)
  ctx.stroke()

  var roseY = c.towerTop + 5.5 * s.scale
  ctx.fillStyle = H.rgba((d.colors && d.colors[11]) || d.accent, 0.16 + bass * 0.34)
  ctx.strokeStyle = nightInk(d, 0.58 + bass * 0.25, 0.44)
  ctx.beginPath()
  ctx.arc(c.spireX, roseY, 2.2 * s.scale, 0, TAU)
  ctx.fill()
  ctx.stroke()

  var doorW = 6 * s.scale, doorH = 8 * s.scale
  ctx.strokeStyle = nightInk(d, 0.62, 0.25)
  ctx.beginPath()
  ctx.moveTo(c.spireX - doorW / 2, c.base)
  ctx.lineTo(c.spireX - doorW / 2, c.base - doorH + doorW / 2)
  ctx.arc(c.spireX, c.base - doorH + doorW / 2, doorW / 2, Math.PI, 0)
  ctx.lineTo(c.spireX + doorW / 2, c.base)
  ctx.stroke()
}

function drawPine(ctx, d, s, pine, mid) {
  var x = pine.x, base = pine.base, top = base - pine.height
  var sway = Math.sin(s.clock * 0.7 + x * 0.03) * mid * 0.45
  ctx.strokeStyle = nightInk(d, 0.38 + pine.depth * 0.38 + mid * 0.08, 0.26)
  ctx.lineWidth = 0.72 + pine.depth * 0.30
  ctx.lineJoin = "round"
  var tip = x + sway
  var points = [
    [tip, top],
    [x - pine.width * 0.20, top + pine.height * 0.31],
    [x - pine.width * 0.08, top + pine.height * 0.28],
    [x - pine.width * 0.33, top + pine.height * 0.54],
    [x - pine.width * 0.13, top + pine.height * 0.49],
    [x - pine.width * 0.48, top + pine.height * 0.78],
    [x - pine.width * 0.18, top + pine.height * 0.71],
    [x - pine.width * 0.58, top + pine.height * 0.96],
    [x - 1.5 * s.scale, base], [x + 1.5 * s.scale, base],
    [x + pine.width * 0.58, top + pine.height * 0.96],
    [x + pine.width * 0.18, top + pine.height * 0.71],
    [x + pine.width * 0.48, top + pine.height * 0.78],
    [x + pine.width * 0.13, top + pine.height * 0.49],
    [x + pine.width * 0.33, top + pine.height * 0.54],
    [x + pine.width * 0.08, top + pine.height * 0.28],
    [x + pine.width * 0.20, top + pine.height * 0.31],
    [tip, top]
  ]
  strokePath(ctx, points)
  ctx.strokeStyle = nightInk(d, 0.20 + pine.depth * 0.24, 0.30)
  strokePath(ctx, [[x, top + pine.height * 0.22], [x, base + 1]])
}

function drawBushes(ctx, d, s, mid) {
  var groups = [[0.005, 0.040, 3], [0.175, 0.190, 4], [0.375, 0.405, 4],
                [0.570, 0.600, 4], [0.720, 0.750, 4], [0.850, 0.865, 3]]
  ctx.strokeStyle = nightInk(d, 0.48 + mid * 0.07, 0.24)
  ctx.lineWidth = 1
  for (var g = 0; g < groups.length; g++) {
    var x0 = s.w * groups[g][0], x1 = s.w * groups[g][1]
    var count = groups[g][2], step = (x1 - x0) / count
    ctx.beginPath()
    ctx.moveTo(x0, groundY(s, x0))
    for (var i = 0; i < count; i++) {
      var left = x0 + i * step
      var center = left + step / 2
      var top = groundY(s, center) - (2.5 + (i % 2) * 1.4) * s.scale
      ctx.quadraticCurveTo(center, top, left + step, groundY(s, left + step))
    }
    ctx.stroke()
  }
}

function drawSmoke(ctx, d, s, mid) {
  ctx.lineWidth = 1
  for (var i = 0; i < s.chimneys.length; i++) {
    var chimney = s.chimneys[i]
    ctx.strokeStyle = nightInk(d, (0.11 + mid * 0.12) * chimney.depth, 0.36)
    var drift = Math.sin(s.clock * 0.32 + i * 1.9) * (0.8 + mid * 1.4)
    ctx.beginPath()
    ctx.moveTo(chimney.x, chimney.y)
    ctx.quadraticCurveTo(chimney.x - 2 + drift, chimney.y - 3 * s.scale,
                         chimney.x + 1 + drift, chimney.y - 5.5 * s.scale)
    ctx.quadraticCurveTo(chimney.x + 4 + drift, chimney.y - 8 * s.scale,
                         chimney.x + 2 + drift * 1.4, chimney.y - 10 * s.scale)
    ctx.stroke()
  }
}

function drawWindows(ctx, d, s, levels, dt) {
  var warm = (d.colors && d.colors[11]) || d.accent
  for (var i = 0; i < s.windows.length; i++) {
    var win = s.windows[i]
    var level = levels.length ? levels[win.band % levels.length] : 0
    var idleGlow = !d.playing && (i === 1 || i === 5) ? 0.22 : 0
    var activeGlow = level > win.threshold
      ? 0.30 + clamp((level - win.threshold) / 0.42, 0, 1) * 0.70 : 0
    var target = Math.max(activeGlow, idleGlow)
    win.value = smoothLevel(win.value, target, dt, 0.12, 0.72)

    if (win.value > 0.06) {
      ctx.fillStyle = H.rgba(warm, 0.04 + win.value * 0.14)
      ctx.fillRect(win.x - 1, win.y - 1, win.width + 2, win.height + 2)
    }
    ctx.strokeStyle = nightInk(d, 0.18 + win.depth * 0.22, 0.20)
    ctx.lineWidth = 1
    ctx.strokeRect(win.x - 0.5, win.y - 0.5, win.width + 1, win.height + 1)
    ctx.fillStyle = H.rgba(warm, 0.10 + win.depth * 0.05 + win.value * 0.82)
    ctx.fillRect(win.x, win.y, win.width, win.height)
    if (win.value > 0.52) {
      ctx.fillStyle = nightInk(d, 0.28 + win.value * 0.38, 0.12)
      ctx.fillRect(win.x + 1, win.y, 1, win.height)
      ctx.fillRect(win.x, win.y + 1, win.width, 1)
    }
  }
}

function drawGround(ctx, d, s, bass) {
  ctx.strokeStyle = nightInk(d, 0.86, 0.18)
  ctx.lineWidth = 1.25
  ctx.beginPath()
  ctx.moveTo(0, groundY(s, 0))
  for (var x = 4; x <= s.w + 4; x += 4) ctx.lineTo(x, groundY(s, x))
  ctx.stroke()

  ctx.strokeStyle = nightInk(d, 0.12 + bass * 0.08, 0.48)
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.moveTo(0, s.base + 4 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.28, s.base + 1 * s.scale,
                       s.w * 0.52, s.base + 5 * s.scale)
  ctx.quadraticCurveTo(s.w * 0.75, s.base + 8 * s.scale,
                       s.w, s.base + 3 * s.scale)
  ctx.stroke()

  ctx.strokeStyle = nightInk(d, 0.30, 0.24)
  for (var i = 0; i < 13; i++) {
    var tx = s.w * (0.025 + i * 0.077)
    var ty = groundY(s, tx)
    ctx.beginPath()
    ctx.moveTo(tx, ty)
    ctx.lineTo(tx - 1.5 * s.scale, ty - (2 + i % 2) * s.scale)
    ctx.moveTo(tx, ty)
    ctx.lineTo(tx + 1.3 * s.scale, ty - (1.5 + (i + 1) % 2) * s.scale)
    ctx.stroke()
  }
}

function drawMeteor(ctx, d, s, dt, beat) {
  if (!s.meteorSparks) s.meteorSparks = []
  if (d.playing && beat > 0.76 && s.prevBeat <= 0.76 && !s.meteor
      && s.clock - s.lastMeteor > 11) {
    var start = 0.10 + (s.meteorSequence * 0.371) % 0.46
    s.meteorSequence++
    s.lastMeteor = s.clock
    s.meteor = {
      x: s.w * start, y: 1 + H.lcgRand01(s.rng) * 2,
      vx: s.w * (0.27 + H.lcgRand01(s.rng) * 0.04),
      vy: s.h * (0.32 + H.lcgRand01(s.rng) * 0.08),
      life: 1,
      trail: [],
      emitClock: 0
    }
  }
  s.prevBeat = beat

  var meteor = s.meteor
  if (meteor) {
    meteor.trail.unshift({ x: meteor.x, y: meteor.y })
    while (meteor.trail.length > 12) meteor.trail.pop()
    meteor.x += meteor.vx * dt
    meteor.y += meteor.vy * dt
    meteor.vy += s.h * 0.025 * dt
    meteor.life -= dt * 0.48
    meteor.emitClock += dt

    while (meteor.emitClock >= 0.085 && s.meteorSparks.length < 14) {
      meteor.emitClock -= 0.085
      var sparkLife = 0.24 + H.lcgRand01(s.rng) * 0.34
      s.meteorSparks.push({
        x: meteor.x - H.lcgRand01(s.rng) * 5 * s.scale,
        y: meteor.y + (H.lcgRand01(s.rng) - 0.5) * 3 * s.scale,
        vx: -meteor.vx * (0.02 + H.lcgRand01(s.rng) * 0.05),
        vy: (H.lcgRand01(s.rng) - 0.5) * s.h * 0.12,
        life: sparkLife,
        maxLife: sparkLife
      })
    }

    ctx.lineCap = "round"
    for (var trailIndex = meteor.trail.length - 1; trailIndex >= 0; trailIndex--) {
      var tail = meteor.trail[trailIndex]
      var next = trailIndex === 0 ? meteor : meteor.trail[trailIndex - 1]
      var nearness = 1 - trailIndex / Math.max(1, meteor.trail.length)
      ctx.strokeStyle = nightInk(d, meteor.life * (0.035 + nearness * 0.15), 0.42)
      ctx.lineWidth = 0.8 + nearness * 2.4
      ctx.beginPath(); ctx.moveTo(tail.x, tail.y); ctx.lineTo(next.x, next.y); ctx.stroke()
      ctx.strokeStyle = nightInk(d, meteor.life * (0.12 + nearness * 0.62), 0.24)
      ctx.lineWidth = 0.55 + nearness * 0.75
      ctx.beginPath(); ctx.moveTo(tail.x, tail.y); ctx.lineTo(next.x, next.y); ctx.stroke()
    }

    ctx.fillStyle = nightInk(d, 0.10 + meteor.life * 0.12, 0.50)
    ctx.beginPath(); ctx.arc(meteor.x, meteor.y, 3.2 * s.scale, 0, TAU); ctx.fill()
    ctx.strokeStyle = nightInk(d, 0.36 + meteor.life * 0.50, 0.28)
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(meteor.x - 3 * s.scale, meteor.y); ctx.lineTo(meteor.x + 3 * s.scale, meteor.y)
    ctx.moveTo(meteor.x, meteor.y - 1.8 * s.scale); ctx.lineTo(meteor.x, meteor.y + 1.8 * s.scale)
    ctx.stroke()
    ctx.fillStyle = H.mixColor(d.foreground, "#ffffff", 0.72, 0.76 + meteor.life * 0.22)
    ctx.beginPath(); ctx.arc(meteor.x, meteor.y, 1.15 * s.scale, 0, TAU); ctx.fill()

    if (meteor.life <= 0 || meteor.x > s.w || meteor.y > s.h * 0.48) s.meteor = null
  }

  for (var sparkIndex = s.meteorSparks.length - 1; sparkIndex >= 0; sparkIndex--) {
    var spark = s.meteorSparks[sparkIndex]
    spark.x += spark.vx * dt
    spark.y += spark.vy * dt
    spark.vy += s.h * 0.08 * dt
    spark.life -= dt
    if (spark.life <= 0) {
      s.meteorSparks.splice(sparkIndex, 1)
      continue
    }
    var sparkFade = spark.life / spark.maxLife
    ctx.fillStyle = nightInk(d, sparkFade * 0.66, 0.36)
    ctx.fillRect(Math.round(spark.x), Math.round(spark.y), 1, 1)
  }
}

function render(ctx, d) {
  var w = d.width, h = d.height
  if (w < 80 || h < 30) return

  var s = d.state.village
  if (!s || s.w !== w || s.h !== h) {
    s = {}
    build(s, w, h, d.frame)
    d.state.village = s
  }

  var dt = clamp((Number(d.frame) - s.frame) * 0.0427, 0, 0.16)
  s.frame = Number(d.frame) || s.frame
  if (d.playing) s.clock += dt

  var bands = d.playing ? (d.bands || []) : []
  var rawBass = bands.length ? H.bandAvg(bands, 0, Math.max(2, Math.floor(bands.length * 0.24))) : 0
  var rawMid = bands.length ? H.bandAvg(bands, Math.floor(bands.length * 0.24),
                                         Math.max(3, Math.floor(bands.length * 0.66))) : 0
  var rawTreble = bands.length ? H.bandAvg(bands, Math.floor(bands.length * 0.66), bands.length) : 0
  s.bass = smoothLevel(s.bass, rawBass, dt, 0.18, 0.72)
  s.mid = smoothLevel(s.mid, rawMid, dt, 0.28, 0.95)
  s.treble = smoothLevel(s.treble, rawTreble, dt, 0.34, 1.10)
  var bass = s.bass, mid = s.mid, treble = s.treble
  var levels = H.resampleBandsLinear(bands, s.windows.length)
  var beat = clamp(d.beatDrop, 0, 1)

  settleBackground(ctx, d, s)
  drawSky(ctx, d, s, treble)
  drawMeteor(ctx, d, s, dt, beat)
  drawHills(ctx, d, s, mid)
  drawMoonPath(ctx, d, s, treble)
  drawSmoke(ctx, d, s, mid)
  for (var i = 0; i < s.houses.length; i++) drawHouse(ctx, d, s, s.houses[i])
  drawChurch(ctx, d, s, bass)
  for (var p = 0; p < s.pines.length; p++) drawPine(ctx, d, s, s.pines[p], mid)
  drawBushes(ctx, d, s, mid)
  drawWindows(ctx, d, s, levels, dt)
  drawGround(ctx, d, s, bass)
}

// Port of cliamp vis_red_sector.go.
.pragma library
.import "helpers.js" as H

var BARS = 5
var HALF_WIDTH = 0.26
var HALF_DEPTH = 0.26
var PITCH = 0.78
var GROUND_Y = -1.05
var MIN_HEIGHT = 0.40
var MAX_HEIGHT = 2.30
var FOCAL = 3.2
var CAMERA_Z = 6.0
var NEAR_DEPTH = 0.35
var ZOOM_AMPLITUDE = 1.5
var ZOOM_RATE = 0.011
var FIT_ZOOM_MIN = 0.55
var FIT_ZOOM_SWING = 0.30
var MAX_STRETCH = 2.0
var COMFORT_DOT_ROWS = 40
var SPIN_Y = 0.105
var SPIN_X = 0.073
var ENVELOPE_RELAX = 0.001
var MIN_ENVELOPE = 0.06
var HEIGHT_RISE = 0.75
var HEIGHT_FALL = 0.28
var STAR_TAGS = 4
var TAG_LOW = 5
var STAR_DIM = 0.6
var DOTS_PER_STAR = 130
var MIN_STARS = 6
var MAX_STARS = 90
var STAR_LANES = 3
var STAR_SPEED = 0.10
var STAR_LANE_SPEEDUP = 0.09
var MAX_LINE_STEPS = 512
var MIN_DOT_ROWS = 4
var MIN_DOT_COLS = 16
var CORNER_X = [-1, 1, 1, -1, -1, 1, 1, -1]
var CORNER_Z = [-1, -1, -1, -1, 1, 1, 1, 1]
var CORNER_TOP = [false, false, true, true, false, false, true, true]
var FACES = [[0, 1, 2, 3], [5, 4, 7, 6], [0, 3, 7, 4], [1, 5, 6, 2], [3, 2, 6, 7], [0, 4, 5, 1]]

function onEnter(state) {
  state.redSector = null
}

function newDriver() {
  return {
    clock: { last: 0, pending: 0 }, frame: 0, dots: null,
    ceiling: new Array(BARS).fill(0), floor: new Array(BARS).fill(1), heights: new Array(BARS).fill(MIN_HEIGHT)
  }
}

function unitLevel(value) {
  return Math.min(1, Math.max(0, value || 0))
}

function advance(rs, bands) {
  for (var bar = 0; bar < BARS; bar++) {
    var level = Math.max(unitLevel(bands[bar * 2]), unitLevel(bands[bar * 2 + 1]))
    rs.ceiling[bar] = level > rs.ceiling[bar] ? level : rs.ceiling[bar] - ENVELOPE_RELAX
    rs.floor[bar] = level < rs.floor[bar] ? level : rs.floor[bar] + ENVELOPE_RELAX
    rs.ceiling[bar] = Math.max(rs.ceiling[bar], rs.floor[bar] + MIN_ENVELOPE)
    var norm = Math.min(1, Math.max(0, (level - rs.floor[bar]) / (rs.ceiling[bar] - rs.floor[bar])))
    var target = MIN_HEIGHT + norm * (MAX_HEIGHT - MIN_HEIGHT)
    rs.heights[bar] += (target - rs.heights[bar]) * (target > rs.heights[bar] ? HEIGHT_RISE : HEIGHT_FALL)
  }
}

function starHash(star, slot) {
  var x = Math.imul(star, 0x9E3779B9) ^ Math.imul(slot + 1, 0x85EBCA6B)
  x ^= x >>> 16
  x = Math.imul(x, 0x7FEB352D)
  x ^= x >>> 15
  x = Math.imul(x, 0x846CA68B)
  x ^= x >>> 16
  return (x >>> 0) / 4294967296
}

function setDot(grid, x, y, tag) {
  if (x < 0 || x >= grid.cols || y < 0 || y >= grid.rows) return
  var i = (y * grid.cols + x) | 0
  if (tag > grid.tags[i]) grid.tags[i] = tag
}

function drawStars(grid, frame) {
  var count = Math.min(MAX_STARS, Math.max(MIN_STARS, Math.floor(grid.rows * grid.cols / DOTS_PER_STAR)))
  for (var star = 1; star <= count; star++) {
    var speed = STAR_SPEED + (star % STAR_LANES) * STAR_LANE_SPEEDUP
    var x = ((starHash(star, 0) * grid.cols - frame * speed) % grid.cols + grid.cols) % grid.cols
    var y = Math.floor(starHash(star, 1) * grid.rows)
    setDot(grid, Math.floor(x), y, Math.min(STAR_TAGS, 1 + Math.floor(starHash(star, 2) * STAR_TAGS)))
  }
}

function place(x, y, z, view) {
  var x1 = x * view.cosY + z * view.sinY
  var z1 = -x * view.sinY + z * view.cosY
  var y1 = y * view.cosX - z1 * view.sinX
  var z2 = y * view.sinX + z1 * view.cosX
  var scale = FOCAL / Math.max(NEAR_DEPTH, z2 + view.camZ)
  return { x: x1, y: y1, z: z2, px: x1 * scale, py: y1 * scale }
}

function fit(grid, frame, view) {
  var hullX = (BARS - 1) / 2 * PITCH + HALF_WIDTH
  var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
  for (var sx = -1; sx <= 1; sx += 2) {
    for (var top = 0; top <= 1; top++) {
      for (var sz = -1; sz <= 1; sz += 2) {
        var corner = place(sx * hullX, GROUND_Y + top * MAX_HEIGHT, sz * HALF_DEPTH, view)
        minX = Math.min(minX, corner.px); maxX = Math.max(maxX, corner.px)
        minY = Math.min(minY, corner.py); maxY = Math.max(maxY, corner.py)
      }
    }
  }
  var zoom = FIT_ZOOM_MIN + FIT_ZOOM_SWING * (0.5 + 0.5 * Math.sin(frame * ZOOM_RATE))
  var fitY = (grid.rows - 1) / Math.max(maxY - minY, 0.001) * zoom
  var stretch = Math.min(MAX_STRETCH, Math.max(1, COMFORT_DOT_ROWS / grid.rows))
  var fitX = Math.min(fitY * stretch, (grid.cols - 1) / Math.max(maxX - minX, 0.001))
  return {
    x: fitX, y: fitY,
    centreX: grid.cols / 2 - (minX + maxX) / 2 * fitX,
    centreY: grid.rows / 2 + (minY + maxY) / 2 * fitY
  }
}

function faceVisible(p1, p2, p3, camZ) {
  var ux = p2.x - p1.x, uy = p2.y - p1.y, uz = p2.z - p1.z
  var vx = p3.x - p2.x, vy = p3.y - p2.y, vz = p3.z - p2.z
  var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
  return nx * p1.x + ny * p1.y + nz * (p1.z + camZ) > 0
}

function drawLine(grid, from, to, tag) {
  var dx = to.sx - from.sx, dy = to.sy - from.sy
  var span = Math.max(Math.abs(dx), Math.abs(dy))
  if (!isFinite(span)) return
  var steps = Math.min(MAX_LINE_STEPS, Math.floor(span) + 1)
  for (var step = 0; step <= steps; step++) {
    var t = step / steps
    setDot(grid, Math.floor(from.sx + dx * t + 0.5), Math.floor(from.sy + dy * t + 0.5), tag)
  }
}

function drawBars(grid, rs, frame) {
  var view = {
    cosY: Math.cos(frame * SPIN_Y), sinY: Math.sin(frame * SPIN_Y),
    cosX: Math.cos(frame * SPIN_X), sinX: Math.sin(frame * SPIN_X),
    camZ: CAMERA_Z + Math.sin(frame * ZOOM_RATE) * ZOOM_AMPLITUDE
  }
  var scale = fit(grid, frame, view)
  for (var bar = 0; bar < BARS; bar++) {
    var baseX = (bar - (BARS - 1) / 2) * PITCH
    var tag = TAG_LOW + H.specTag((rs.heights[bar] - MIN_HEIGHT) / (MAX_HEIGHT - MIN_HEIGHT))
    var corners = []
    for (var c = 0; c < 8; c++) {
      var corner = place(baseX + CORNER_X[c] * HALF_WIDTH, CORNER_TOP[c] ? GROUND_Y + rs.heights[bar] : GROUND_Y,
                         CORNER_Z[c] * HALF_DEPTH, view)
      corner.sx = scale.centreX + corner.px * scale.x
      corner.sy = scale.centreY - corner.py * scale.y
      corners.push(corner)
    }
    for (var f = 0; f < FACES.length; f++) {
      var face = FACES[f]
      if (!faceVisible(corners[face[0]], corners[face[1]], corners[face[2]], view.camZ)) continue
      for (var e = 0; e < 4; e++) drawLine(grid, corners[face[e]], corners[face[(e + 1) % 4]], tag)
    }
  }
}

function tagColors(d) {
  var spectrum = H.playerSpectrum(d)
  var quiet = spectrum.map(function (color) { return H.mixColor(color, "#000000", 1 - STAR_DIM, 1) })
  return [null, H.rgba(d.dim, 1)].concat(quiet, H.playerTiers(d))
}

function render(ctx, d) {
  var cols = Math.floor(d.width), rows = Math.floor(d.height)
  if (rows < MIN_DOT_ROWS || cols < MIN_DOT_COLS) return

  var s = d.state
  if (!s.redSector) s.redSector = newDriver()
  var rs = s.redSector
  var ticks = H.cliampTicks(rs.clock)
  var bands = H.cliampBands(d.bands, d.bandEdges)
  for (var tick = 0; tick < ticks; tick++) advance(rs, bands)
  rs.frame += ticks

  if (!rs.dots || rs.dots.length !== rows * cols) rs.dots = new Int8Array(rows * cols)
  else rs.dots.fill(0)
  var grid = { tags: rs.dots, cols: cols, rows: rows }
  var frame = rs.frame + H.cliampTickFraction(rs.clock)
  drawStars(grid, frame)
  drawBars(grid, rs, frame)
  H.paintTagGrid(ctx, grid.tags, cols, rows, tagColors(d))
}

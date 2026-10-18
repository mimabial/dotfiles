.pragma library
.import "helpers.js" as VisualizerHelpers

var BLOBS = [
  { cx: 0.15, cy: 0.35, rx: 0.30, ry: 0.70, color: -2, weight: 0.85, drift: 1.0 },
  { cx: 0.30, cy: 0.70, rx: 0.22, ry: 0.55, color: 2,  weight: 0.80, drift: -1.1 },
  { cx: 0.50, cy: 0.50, rx: 0.35, ry: 0.80, color: 6,  weight: 1.00, drift: 1.3 },
  { cx: 0.72, cy: 0.30, rx: 0.25, ry: 0.60, color: -1, weight: 0.90, drift: 0.9 },
  { cx: 0.85, cy: 0.60, rx: 0.28, ry: 0.65, color: 4,  weight: 0.85, drift: -0.7 }
]

var MAX_DELTA = 0.42
var SAT_CAP = 0.82
var ACCENT_PULL = 0.15
var ALPHA = 0.50
var MID_ALPHA = 0.175

function shortestHueRotation(from, to) {
  return ((to - from + 540) % 360) - 180
}

function tint(color, surfaceLightness, weight) {
  var src = VisualizerHelpers.hsl(color)
  var up = 1 - surfaceLightness
  var room = Math.max(up, surfaceLightness)
  var delta = Math.min(MAX_DELTA * weight, room * 0.85)
  var target = surfaceLightness + (up >= surfaceLightness ? delta : -delta)
  var reach = delta / MAX_DELTA
  return VisualizerHelpers.hueShift(color, 0, Math.min(src.s, SAT_CAP * (0.55 + 0.45 * reach)), target)
}

function accentTint(accent, palette, surfaceLightness, weight) {
  var src = VisualizerHelpers.hsl(accent)
  var left = palette[6], right = palette[4]
  if (src.s === 0 || !left || !right) return tint(accent, surfaceLightness, weight)
  var lh = VisualizerHelpers.hsl(left).h
  var mid = lh + shortestHueRotation(lh, VisualizerHelpers.hsl(right).h) / 2
  return tint(VisualizerHelpers.hueShift(accent, shortestHueRotation(src.h, mid) * ACCENT_PULL), surfaceLightness, weight)
}

function render(canvas, frameData) {
  if (!frameData.playing) return

  var width = frameData.width, height = frameData.height
  var t = frameData.frame * 0.02
  var beat = frameData.beatDrop || 0
  var bass = VisualizerHelpers.bandAvg(frameData.bands || [], 0, 5)
  var palette = frameData.colors || []
  var surfaceLightness = VisualizerHelpers.hsl(frameData.surface).l

  var swell = 1.25 + bass * 0.25 + beat * 0.20
  var sway = 1.0 + bass * 0.5 + beat * 0.4
  var alpha = frameData.backgroundPulse ? Math.min(0.85, 0.45 + beat * 0.25 + bass * 0.15) : ALPHA
  var midAlpha = frameData.backgroundPulse ? alpha * 0.35 : MID_ALPHA

  for (var i = 0; i < BLOBS.length; i++) {
    var blob = BLOBS[i]
    var core = blob.color === -2
      ? tint(frameData.success || frameData.accent, surfaceLightness, blob.weight)
      : blob.color >= 0 && palette[blob.color]
        ? tint(palette[blob.color], surfaceLightness, blob.weight)
        : accentTint(frameData.accent, palette, surfaceLightness, blob.weight)

    var rx = blob.rx * width * swell
    var ry = blob.ry * height * swell
    if (rx <= 0 || ry <= 0) continue

    var centerX = (blob.cx + Math.sin(t * blob.drift + i * 1.5) * 0.06 * sway) * width
    var centerY = (blob.cy + Math.cos(t * blob.drift * 0.8 + i * 2.0) * 0.08 * sway) * height

    canvas.save()
    canvas.translate(centerX, centerY)
    canvas.scale(rx, ry)
    var gradient = canvas.createRadialGradient(0, 0, 0, 0, 0, 1)
    gradient.addColorStop(0, VisualizerHelpers.rgba(core, alpha))
    gradient.addColorStop(0.6, VisualizerHelpers.mixColor(core, frameData.surface, 0.25, midAlpha))
    gradient.addColorStop(1, VisualizerHelpers.rgba(core, 0))
    canvas.fillStyle = gradient
    canvas.fillRect(-1, -1, 2, 2)
    canvas.restore()
  }
}

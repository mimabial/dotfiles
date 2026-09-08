// Nebula — drifting elliptical blobs painted behind the active visualizer.
// Not a mode: Player.qml paints this into its own Canvas below the visualizer and applies
// a single opacity to the flattened result. Scaling each blob instead (globalAlpha) still
// scales them one draw at a time, so the overlaps would keep stacking.
.pragma library
.import "helpers.js" as H

// Blobs take their hue straight from the theme's terminal palette rather than from
// anything synthesised, and three rules keep the result a nebula rather than mud:
//
// 1. Ordered by cx along a coherent slice of the palette (success -> c2 -> teal ->
//    accent -> blue), so horizontally adjacent blobs are adjacent in hue and blend into
//    one sweep. Picking colours from around the whole wheel puts clashes side by side.
// 2. Lightness is a bounded step away from the player's own surface, in whichever
//    direction has headroom. A fixed lightness leaves the contrast against the surface
//    uncontrolled -- 0.38 is a +0.22 step over a #2C2525 surface but a -0.57 step under
//    a near-white one, which is why the wash landed far heavier on light themes.
// 3. The accent is the one blob that is not a palette slot -- it tracks album art and
//    can land anywhere on the wheel, in the middle of that ordered slice -- so its hue
//    is pulled toward its two neighbours before use.
//
// color is an index into d.colors; -1 means accent and -2 means success.
var BLOBS = [
  { cx: 0.15, cy: 0.35, rx: 0.30, ry: 0.70, color: -2, weight: 0.85, drift: 1.0 },
  { cx: 0.30, cy: 0.70, rx: 0.22, ry: 0.55, color: 2,  weight: 0.80, drift: -1.1 },
  { cx: 0.50, cy: 0.50, rx: 0.35, ry: 0.80, color: 6,  weight: 1.00, drift: 1.3 },
  { cx: 0.72, cy: 0.30, rx: 0.25, ry: 0.60, color: -1, weight: 0.90, drift: 0.9 },
  { cx: 0.85, cy: 0.60, rx: 0.28, ry: 0.65, color: 4,  weight: 0.85, drift: -0.7 }
]

// Lightness distance from the surface at weight 1. Tuned so the four palette blobs land
// within 0.01 of the fixed values this replaced on a dark theme; the accent core is
// deliberately lower than its old 0.50.
var MAX_DELTA = 0.42
// Decorative fills never want a palette colour at full chroma, and less of it still when
// the surface leaves little lightness headroom to separate them from it.
var SAT_CAP = 0.82
var ACCENT_PULL = 0.15
var ALPHA = 0.50
var MID_ALPHA = 0.175

// Shortest signed rotation from one hue to another, in degrees.
function arcDelta(from, to) {
  return ((to - from + 540) % 360) - 180
}

function tint(color, surfaceL, weight) {
  var src = H.hsl(color)
  var up = 1 - surfaceL
  var room = Math.max(up, surfaceL)
  var delta = Math.min(MAX_DELTA * weight, room * 0.85)
  var target = surfaceL + (up >= surfaceL ? delta : -delta)
  var reach = delta / MAX_DELTA
  return H.hueShift(color, 0, Math.min(src.s, SAT_CAP * (0.55 + 0.45 * reach)), target)
}

function accentTint(accent, palette, surfaceL, weight) {
  var src = H.hsl(accent)
  var left = palette[6], right = palette[4]
  if (src.s === 0 || !left || !right) return tint(accent, surfaceL, weight)
  var lh = H.hsl(left).h
  var mid = lh + arcDelta(lh, H.hsl(right).h) / 2
  return tint(H.hueShift(accent, arcDelta(src.h, mid) * ACCENT_PULL), surfaceL, weight)
}

function render(ctx, d) {
  if (!d.playing) return

  var w = d.width, h = d.height
  var t = d.frame * 0.02
  var beat = d.beatDrop || 0
  var bass = H.bandAvg(d.bands || [], 0, 5)
  var palette = d.colors || []
  var surfaceL = H.hsl(d.surface).l

  // Omaramp's alpha pulse is optional; movement and swelling remain audio-reactive either way.
  var swell = 1.25 + bass * 0.25 + beat * 0.20
  var sway = 1.0 + bass * 0.5 + beat * 0.4
  var alpha = d.backgroundPulse ? Math.min(0.85, 0.45 + beat * 0.25 + bass * 0.15) : ALPHA
  var midAlpha = d.backgroundPulse ? alpha * 0.35 : MID_ALPHA

  for (var i = 0; i < BLOBS.length; i++) {
    var bl = BLOBS[i]
    var core = bl.color === -2
      ? tint(d.success || d.accent, surfaceL, bl.weight)
      : bl.color >= 0 && palette[bl.color]
        ? tint(palette[bl.color], surfaceL, bl.weight)
        : accentTint(d.accent, palette, surfaceL, bl.weight)

    var rx = bl.rx * w * swell
    var ry = bl.ry * h * swell
    if (rx <= 0 || ry <= 0) continue

    var bx = (bl.cx + Math.sin(t * bl.drift + i * 1.5) * 0.06 * sway) * w
    var by = (bl.cy + Math.cos(t * bl.drift * 0.8 + i * 2.0) * 0.08 * sway) * h

    // A unit-circle gradient under a scale transform, so rx and ry describe an ellipse
    // instead of collapsing into whichever of the two is larger. The fill covers the
    // blob's bounding box rather than the whole canvas, which is not a speed win here:
    // measured at 500x61 the transform costs more than the saved area, ~0.12ms/frame
    // against ~0.10 for a full-canvas circle. Both are noise against the frame tick.
    ctx.save()
    ctx.translate(bx, by)
    ctx.scale(rx, ry)
    var grad = ctx.createRadialGradient(0, 0, 0, 0, 0, 1)
    grad.addColorStop(0, H.rgba(core, alpha))
    // Midpoint sinks toward the surface so blobs stay readable behind the visualizer.
    grad.addColorStop(0.6, H.mixColor(core, d.surface, 0.25, midAlpha))
    grad.addColorStop(1, H.rgba(core, 0))
    ctx.fillStyle = grad
    ctx.fillRect(-1, -1, 2, 2)
    ctx.restore()
  }
}

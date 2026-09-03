// Nebula — drifting radial blobs painted behind the active visualizer.
// Not a mode: Player.qml renders this first when the background is enabled.
.pragma library
.import "helpers.js" as H

// Blobs take their hue straight from the theme's terminal palette rather than from
// anything synthesised, and two rules keep the result a nebula rather than mud:
//
// 1. Ordered by cx along a coherent slice of the palette (pink -> mauve -> accent ->
//    blue -> teal), so horizontally adjacent blobs are adjacent in hue and blend into
//    one sweep. Picking colours from around the whole wheel puts clashes side by side.
// 2. Darkened via shade(). Palette colours are chosen to read as text on a dark
//    background -- at their native lightness five of them composite to a bright wash.
//
// color is an index into d.colors; -1 means the accent, used for the brighter core.
var BLOBS = [
  { cx: 0.15, cy: 0.35, rx: 0.30, ry: 0.70, color: 1,  light: 0.38, drift: 1.0 },
  { cx: 0.30, cy: 0.70, rx: 0.22, ry: 0.55, color: 5,  light: 0.36, drift: -1.1 },
  { cx: 0.50, cy: 0.50, rx: 0.35, ry: 0.80, color: -1, light: 0.50, drift: 1.3 },
  { cx: 0.72, cy: 0.30, rx: 0.25, ry: 0.60, color: 4,  light: 0.40, drift: 0.9 },
  { cx: 0.85, cy: 0.60, rx: 0.28, ry: 0.65, color: 6,  light: 0.38, drift: -0.7 }
]

function render(ctx, d) {
  if (!d.playing) return

  var w = d.width, h = d.height
  var t = d.frame * 0.02
  var beat = d.beatDrop || 0
  var bass = H.bandAvg(d.bands || [], 0, 5)

  for (var i = 0; i < BLOBS.length; i++) {
    var bl = BLOBS[i]
    var palette = d.colors || []
    var core = H.shade(bl.color >= 0 && palette[bl.color] ? palette[bl.color] : d.accent, bl.light)

    var bx = (bl.cx + Math.sin(t * bl.drift + i * 1.5) * 0.12) * w
    var by = (bl.cy + Math.cos(t * bl.drift * 0.8 + i * 2.0) * 0.15) * h
    var radius = Math.max(bl.rx * w * (1.0 + bass * 0.4 + beat * 0.3),
                          bl.ry * h * (1.0 + bass * 0.3 + beat * 0.2))
    var alpha = 0.45 + beat * 0.25 + bass * 0.15

    var grad = ctx.createRadialGradient(bx, by, 0, bx, by, radius)
    grad.addColorStop(0, H.rgba(core, alpha.toFixed(2)))
    // Midpoint sinks toward the surface so blobs stay readable behind the visualizer.
    grad.addColorStop(0.6, H.mixColor(core, d.surface, 0.45, (alpha * 0.35).toFixed(2)))
    grad.addColorStop(1, H.rgba(core, 0))

    ctx.fillStyle = grad
    ctx.fillRect(0, 0, w, h)
  }
}

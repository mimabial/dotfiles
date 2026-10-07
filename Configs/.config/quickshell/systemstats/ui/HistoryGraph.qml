pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Bars are snapped to device pixels so 1px marks stay crisp on fractional scales.
Canvas {
  id: root

  property var series: []
  property var colors: []
  property var ceiling
  property real minimumCeiling: 1
  property real headroom: 1.06
  property int barWidth: 2
  property int gap: 1
  property bool showBaseline: true
  property bool showGaps: false
  property color baselineColor: Util.alpha(Color.popups.text, 0.14)
  property color gapColor: Util.alpha(Color.popups.text, 0.5)

  readonly property int pitch: Math.max(1, barWidth + gap)
  readonly property int capacity: Math.max(1, Math.floor((width + gap) / pitch))

  antialiasing: false
  renderStrategy: Canvas.Cooperative

  onSeriesChanged: requestPaint()
  onColorsChanged: requestPaint()
  onCeilingChanged: requestPaint()
  onBarWidthChanged: requestPaint()
  onShowGapsChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onBaselineColorChanged: requestPaint()
  onGapColorChanged: requestPaint()
  onVisibleChanged: if (visible) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.clearRect(0, 0, width, height)
    if (width <= 0 || height <= 0) return

    var dpr = (Screen && Screen.devicePixelRatio) ? Screen.devicePixelRatio : 1
    var snap = function(v) { return Math.round(v * dpr) / dpr }
    var list = Array.isArray(root.series) ? root.series : []
    var count = list.length
    var n = root.capacity
    var len = 0
    for (var s = 0; s < count; s++) if (list[s] && list[s].length > len) len = list[s].length

    var baseH = root.showBaseline ? 1 : 0
    var usable = Math.max(1, height - baseH)
    var max = Number(root.ceiling)
    if (root.ceiling === undefined) {
      max = Math.max(0.000001, Number(root.minimumCeiling) || 0)
      for (var i = Math.max(0, len - n); i < len; i++) {
        var sum = 0
        for (var k = 0; k < count; k++) sum += Number(list[k] ? list[k][i] : 0) || 0
        if (sum > max) max = sum
      }
      max *= root.headroom
    }

    for (var b = 0; b < n; b++) {
      var idx = len - n + b
      if (idx < 0) continue
      var x = width - (n - b) * root.pitch + root.gap
      var y = height - baseH
      for (var c = 0; c < count; c++) {
        var v = Number(list[c] ? list[c][idx] : 0) || 0
        if (v <= 0) continue
        var h = Math.min(usable, v / max * usable)
        if (h < 1 / dpr) h = 1 / dpr
        var top = snap(y - h)
        var bottom = snap(y)
        if (bottom - top < 1 / dpr) top = bottom - 1 / dpr
        ctx.fillStyle = root.colors[c] || Color.accent
        ctx.fillRect(snap(x), top, Math.max(1 / dpr, snap(root.barWidth)), bottom - top)
        y -= h
      }
    }

    if (root.showBaseline) {
      ctx.fillStyle = root.baselineColor
      ctx.fillRect(0, height - 1, width, 1)
    }
    if (root.showGaps) {
      ctx.fillStyle = root.gapColor
      for (var gap = 0; gap < n; gap++) {
        var gapIndex = len - n + gap
        if (gapIndex < 0) continue
        var missing = true
        for (var line = 0; line < count; line++) {
          var reading = list[line] ? list[line][gapIndex] : null
          if (reading !== null && reading !== undefined && isFinite(Number(reading))) { missing = false; break }
        }
        if (missing) ctx.fillRect(snap(width - (n - gap) * root.pitch + root.gap), height - 4, Math.max(1 / dpr, snap(root.barWidth)), 2)
      }
    }
  }
}

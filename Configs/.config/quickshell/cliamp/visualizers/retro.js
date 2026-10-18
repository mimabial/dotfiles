.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, width = frameData.width, height = frameData.height, count = frameData.count, frame = frameData.frame
  var horizon = height * 0.4
  var cx = width / 2.0
  var tiers = VisualizerHelpers.specTiers(frameData)

  var sunR = horizon * 0.85
  canvas.fillStyle = tiers[1]
  for (var sy = 0; sy < horizon; sy++) {
    var rowDist = horizon - sy
    if (rowDist > sunR) continue
    var halfW = Math.sqrt(sunR * sunR - rowDist * rowDist)
    if (rowDist < sunR * 0.5) {
      var sw = Math.max(1, Math.floor(sunR * 0.15))
      if (Math.floor(rowDist / sw) % 2 === 1) continue
    }
    canvas.fillRect(cx - halfW, sy, halfW * 2, 1)
  }

  canvas.strokeStyle = tiers[0]
  canvas.lineWidth = 1
  var numV = 18
  for (var vi = 0; vi <= numV; vi++) {
    canvas.beginPath()
    canvas.moveTo(cx, horizon)
    canvas.lineTo(vi * width / numV, height)
    canvas.stroke()
  }
  var scroll = (frame * 0.08) % 1.0
  var numH = 10
  for (var hi = 0; hi < numH; hi++) {
    var z = (hi + scroll) / numH
    if (z > 1.0) z -= 1.0
    var hy = horizon + 1 + z * z * (height - horizon - 2)
    if (hy > horizon && hy < height) {
      canvas.beginPath()
      canvas.moveTo(0, hy)
      canvas.lineTo(width, hy)
      canvas.stroke()
    }
  }

  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, 1)
  canvas.lineWidth = 2
  canvas.beginPath()
  var maxWave = horizon * 0.85
  for (var rx = 0; rx < width; rx++) {
    var bandF = rx / (width - 1) * (count - 1)
    var bi = Math.floor(bandF)
    var frac = bandF - bi
    var t = (1 - Math.cos(frac * Math.PI)) / 2
    var level = Math.max(0.03, frameData.playing ? (bi >= count - 1 ? (bands[count-1] || 0) :
                (bands[bi] || 0) * (1 - t) + (bands[bi+1] || 0) * t) : 0)
    var ry = horizon - level * maxWave
    if (rx === 0) canvas.moveTo(rx, ry)
    else canvas.lineTo(rx, ry)
  }
  canvas.stroke()
}

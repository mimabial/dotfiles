.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands || []
  var width = frameData.width, height = frameData.height, frame = frameData.frame || 0
  var isPlaying = frameData.playing
  var midY = height / 2.0

  var bass = VisualizerHelpers.bandAvg(bands, 0, 4)
  var mids = VisualizerHelpers.bandAvg(bands, 4, 12)
  var highs = VisualizerHelpers.bandAvg(bands, 12, 24)
  var totalEnergy = bass * 0.5 + mids * 0.35 + highs * 0.15
  var beatDrop = frameData.beatDrop || 0

  if (!isPlaying || totalEnergy < 0.005) {
    canvas.strokeStyle = VisualizerHelpers.rgba(frameData.dim, 0.35)
    canvas.lineWidth = 1.0
    canvas.beginPath()
    canvas.moveTo(0, midY)
    canvas.lineTo(width, midY)
    canvas.stroke()
    return
  }

  var maxSafe = height * 0.38
  var t = frame * 0.08

  var harmonics = [
    { n: 1, omega: 1.0, amp: Math.min(maxSafe, (height * 0.06) + bass * (height * 0.26) + beatDrop * (height * 0.08)) },
    { n: 2, omega: 1.8, amp: Math.min(maxSafe * 0.75, (height * 0.04) + mids * (height * 0.20)) },
    { n: 3, omega: 2.7, amp: Math.min(maxSafe * 0.55, (height * 0.03) + highs * (height * 0.16)) },
    { n: 4, omega: 3.9, amp: Math.min(maxSafe * 0.35, (height * 0.02) + highs * (height * 0.10)) }
  ]

  canvas.beginPath()
  canvas.moveTo(0, midY)
  for (var x = 0; x <= width; x += 2) {
    var xNorm = x / width
    var yDisp = 0
    for (var k = 0; k < harmonics.length; k++) {
      var hItem = harmonics[k]
      yDisp += hItem.amp * Math.sin(hItem.n * Math.PI * xNorm) * Math.cos(hItem.omega * t)
    }
    canvas.lineTo(x, midY - yDisp)
  }
  canvas.lineTo(width, midY)
  canvas.closePath()
  canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, 0.12)
  canvas.fill()

  canvas.lineWidth = 1.2
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.45)
  canvas.beginPath()
  for (var x2 = 0; x2 <= width; x2 += 2) {
    var xN2 = x2 / width
    var y2 = harmonics[1].amp * Math.sin(2.0 * Math.PI * xN2) * Math.cos(1.8 * t) +
             harmonics[2].amp * Math.sin(3.0 * Math.PI * xN2) * Math.cos(2.7 * t)
    var yPos2 = midY - y2
    if (x2 === 0) canvas.moveTo(x2, yPos2)
    else canvas.lineTo(x2, yPos2)
  }
  canvas.stroke()

  canvas.lineWidth = 2.2
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.95)
  canvas.beginPath()
  for (var x3 = 0; x3 <= width; x3 += 2) {
    var xN3 = x3 / width
    var y3 = 0
    for (var m = 0; m < harmonics.length; m++) {
      var hm = harmonics[m]
      y3 += hm.amp * Math.sin(hm.n * Math.PI * xN3) * Math.cos(hm.omega * t)
    }
    var yPos3 = midY - y3
    if (x3 === 0) canvas.moveTo(x3, yPos3)
    else canvas.lineTo(x3, yPos3)
  }
  canvas.stroke()

  canvas.lineWidth = 1.0
  canvas.strokeStyle = VisualizerHelpers.rgba(frameData.foreground, 0.90)
  canvas.beginPath()
  for (var x4 = 0; x4 <= width; x4 += 2) {
    var xN4 = x4 / width
    var y4 = 0
    for (var p = 0; p < harmonics.length; p++) {
      var hp = harmonics[p]
      y4 += hp.amp * Math.sin(hp.n * Math.PI * xN4) * Math.cos(hp.omega * t)
    }
    var yPos4 = midY - y4
    if (x4 === 0) canvas.moveTo(x4, yPos4)
    else canvas.lineTo(x4, yPos4)
  }
  canvas.stroke()
}

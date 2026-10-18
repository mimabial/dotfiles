.pragma library
.import "helpers.js" as VisualizerHelpers

function render(canvas, frameData) {
  var bands = frameData.bands, height = frameData.height, width = frameData.width, frame = frameData.frame
  var playing = frameData.playing
  var state = frameData.state

  var charW = 11
  var charH = 10
  var numCols = Math.floor(width / charW)
  var numRows = Math.floor(height / charH)
  if (numCols < 1 || numRows < 1) return

  if (!state.matrixDrops || state.matrixDrops.length !== numCols) {
    state.matrixDrops = []
    for (var i = 0; i < numCols; i++) {
      state.matrixDrops.push({
        y: Math.random() * numRows,
        speed: 0.035 + Math.random() * 0.055,
        length: 3 + Math.floor(Math.random() * 4),
        glyphSeed: Math.floor(Math.random() * 10000)
      })
    }
  }

  var cols = VisualizerHelpers.resampleBandsLinear(bands, numCols)
  var glyphs = "0123456789ABCDEFλπΣΩ#%*+~=<>:?ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ"

  var c2 = (frameData.colors || [])[2] || frameData.foreground
  var headHot = VisualizerHelpers.rgba(c2, 1), headCool = VisualizerHelpers.mixColor(c2, frameData.accent, 0.4, 1)

  canvas.save()
  canvas.font = "bold 9px monospace"
  canvas.textAlign = "center"
  canvas.textBaseline = "middle"

  for (var c = 0; c < numCols; c++) {
    var energy = playing ? Math.min(1.0, Math.max(0.0, cols[c] || 0)) : 0.05
    var drop = state.matrixDrops[c]
    var cx = c * charW + charW / 2

    var currentSpeed = drop.speed * (1.0 + energy * 1.3)
    drop.y += currentSpeed
    if (drop.y - drop.length > numRows) {
      drop.y = -Math.random() * 3
      drop.length = 3 + Math.floor(Math.random() * 4)
      drop.speed = 0.03 + Math.random() * 0.05
      drop.glyphSeed = Math.floor(Math.random() * 10000)
    }

    var headY = Math.floor(drop.y)

    for (var l = 0; l <= drop.length; l++) {
      var row = headY - l
      if (row < 0 || row >= numRows) continue

      var cy = row * charH + charH / 2

      var gIdx = (drop.glyphSeed + row * 17 + Math.floor(frame / 16)) % glyphs.length
      var ch = glyphs[gIdx]

      if (l === 0) {
        canvas.fillStyle = energy > 0.4 ? headHot : headCool
      } else {
        var alpha = (1.0 - (l / drop.length)) * (0.35 + energy * 0.65)
        if (l === 1) canvas.fillStyle = VisualizerHelpers.mixColor(frameData.accent, c2, 0.4, alpha.toFixed(2))
        else canvas.fillStyle = VisualizerHelpers.rgba(frameData.accent, alpha.toFixed(2))
      }

      canvas.fillText(ch, cx, cy)
    }
  }

  canvas.restore()
}

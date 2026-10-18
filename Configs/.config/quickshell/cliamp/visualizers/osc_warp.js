.pragma library
.import "helpers.js" as VisualizerHelpers

function sampleAt(samples, position) {
  if (!samples || samples.length === 0) return 0
  var index = Math.max(0, Math.min(samples.length - 1, position))
  var lower = Math.floor(index), upper = Math.min(samples.length - 1, lower + 1)
  var mix = index - lower
  return Number(samples[lower] || 0) * (1 - mix) + Number(samples[upper] || 0) * mix
}

function rotateProject(x, y, z, rotX, rotY, rotZ, width, height) {
  var cosY = Math.cos(rotY), sinY = Math.sin(rotY)
  var x1 = x * cosY + z * sinY, z1 = -x * sinY + z * cosY
  var cosX = Math.cos(rotX), sinX = Math.sin(rotX)
  var y1 = y * cosX - z1 * sinX, z2 = y * sinX + z1 * cosX
  var cosZ = Math.cos(rotZ), sinZ = Math.sin(rotZ)
  var x2 = x1 * cosZ - y1 * sinZ, y2 = x1 * sinZ + y1 * cosZ
  var perspective = 4.2 / Math.max(2.2, 4.2 - z2)
  return { x: width / 2 + x2 * width * 0.26 * perspective,
    y: height / 2 + y2 * height * 0.29 * perspective, z: z2,
    depth: Math.max(0, Math.min(1, (z2 + 1.7) / 3.4)) }
}

function renderTrail(canvas, d, points, freshness, highs, impulse) {
  var order = []
  for (var i = 0; i < points.length - 1; i++) order.push(i)
  order.sort(function(a, b) { return (points[a].z + points[a + 1].z) - (points[b].z + points[b + 1].z) })
  for (var item = 0; item < order.length; item++) {
    var index = order[item], first = points[index], second = points[index + 1]
    var depth = (first.depth + second.depth) / 2
    var energy = Math.max(first.energy, second.energy)
    var alpha = freshness * freshness * (0.07 + depth * 0.42 + energy * 0.38 + highs * 0.08)
    var whiteMix = 0.04 + depth * 0.14 + impulse * energy * 0.46
    canvas.strokeStyle = VisualizerHelpers.mixColor(d.accent, d.foreground, whiteMix, Math.min(0.96, alpha))
    canvas.lineWidth = 0.55 + freshness * 0.65 + depth * 0.25
    canvas.beginPath(); canvas.moveTo(first.x, first.y); canvas.lineTo(second.x, second.y); canvas.stroke()
  }
}

function renderBeads(canvas, d, points, impulse) {
  for (var i = 1; i < points.length - 1; i++) {
    var energy = points[i].energy
    var waveformPeak = energy > 0.26 && energy >= points[i - 1].energy && energy >= points[i + 1].energy
    var beatMarker = impulse > 0.20 && i % 7 === 0
    if (!waveformPeak && !beatMarker) continue
    var intensity = Math.min(1, Math.max(energy, impulse * 0.78))
    canvas.fillStyle = VisualizerHelpers.rgba(d.accent, 0.12 + intensity * 0.22)
    canvas.beginPath(); canvas.arc(points[i].x, points[i].y, 2.4 + intensity * 1.5, 0, Math.PI * 2); canvas.fill()
    canvas.fillStyle = VisualizerHelpers.mixColor(d.accent, d.foreground, 0.48 + intensity * 0.42, 0.62 + intensity * 0.34)
    canvas.beginPath(); canvas.arc(points[i].x, points[i].y, 1.0 + intensity * 1.15, 0, Math.PI * 2); canvas.fill()
  }
}

function rotationPose(s, bass, elapsedSeconds) {
  if (s.warpOrbit === undefined) {
    s.warpOrbit = 0
    s.warpOrbitSpeed = 0.20
  }
  var targetSpeed = 0.20 + bass * 0.16 + s.warpImpulse * 0.28
  var speedTau = targetSpeed > s.warpOrbitSpeed ? 0.18 : 0.68
  s.warpOrbitSpeed += (targetSpeed - s.warpOrbitSpeed) * (1 - Math.exp(-elapsedSeconds / speedTau))
  s.warpOrbit += s.warpOrbitSpeed * elapsedSeconds
  return { x: 0, y: s.warpOrbit, z: 0 }
}

function render(canvas, frameData) {
  var width = frameData.width, height = frameData.height, animationState = frameData.state, now = Date.now()
  var stereo = frameData.waveStereo || {}, left = stereo.left || [], right = stereo.right || []
  var bands = frameData.bands || [], bass = VisualizerHelpers.bandAvg(bands, 0, 5)
  var mids = VisualizerHelpers.bandAvg(bands, 5, 14), highs = VisualizerHelpers.bandAvg(bands, 14, 24)
  if (animationState.warpGain === undefined) {
    animationState.warpGain = 1; animationState.warpLastTime = now; animationState.warpTime = 0
    animationState.warpImpulse = 0; animationState.warpPrevBeat = 0; animationState.warpTrails = []
  }
  var elapsedSeconds = Math.min(0.12, Math.max(0.001, (now - animationState.warpLastTime) / 1000))
  animationState.warpLastTime = now; animationState.warpTime += elapsedSeconds

  var peak = 0
  for (var i = 0; i < left.length && i < right.length; i++)
    peak = Math.max(peak, Math.abs(Number(left[i] || 0)), Math.abs(Number(right[i] || 0)))
  var targetGain = frameData.playing && peak > 0.0005 ? Math.max(1, Math.min(24, 0.72 / peak)) : 1
  var gainTau = targetGain < animationState.warpGain ? 0.06 : 0.55
  animationState.warpGain += (targetGain - animationState.warpGain) * (1 - Math.exp(-elapsedSeconds / gainTau))

  var beat = frameData.beatDrop || 0
  if (beat > 0.72 && animationState.warpPrevBeat <= 0.72) animationState.warpImpulse = 1
  else animationState.warpImpulse *= Math.exp(-elapsedSeconds / 0.20)
  animationState.warpPrevBeat = beat

  var pose = rotationPose(animationState, bass, elapsedSeconds)
  var rotX = pose.x, rotY = pose.y, rotZ = pose.z
  var nodes = 112, points = [], waveLength = Math.min(left.length, right.length)
  var radiusScale = 1 + bass * 0.07 + animationState.warpImpulse * 0.10
  for (var node = 0; node <= nodes; node++) {
    var progress = node / nodes, u = progress * Math.PI * 2
    var position = progress * Math.max(0, waveLength - 1)
    var l = frameData.playing ? sampleAt(left, position) : 0
    var r = frameData.playing ? sampleAt(right, position) : 0
    var seam = Math.pow(Math.sin(Math.PI * progress), 2)
    var mid = Math.max(-1, Math.min(1, (l + r) * 0.5 * animationState.warpGain)) * seam
    var side = Math.max(-1, Math.min(1, (l - r) * 0.5 * animationState.warpGain)) * seam
    var sinU = Math.sin(u), cosU = Math.cos(u)
    var radial = 1.02 * radiusScale
    var x = radial * cosU
    var y = (0.45 * Math.sin(4 * u) + 0.06 * Math.sin(3 * u + 0.40)) * radiusScale
    var z = radial * sinU + mid * (0.03 + highs * 0.015) + side * 0.02
    var projected = rotateProject(x, y, z, rotX, rotY, rotZ, width, height)
    projected.energy = Math.min(1, Math.abs(mid) * 0.65 + Math.abs(side) * 0.35)
    points.push(projected)
  }

  animationState.warpTrails.push(points)
  while (animationState.warpTrails.length > 2) animationState.warpTrails.shift()
  for (var trail = 0; trail < animationState.warpTrails.length; trail++) {
    var freshness = (trail + 1) / animationState.warpTrails.length
    if (trail === animationState.warpTrails.length - 1) {
      canvas.strokeStyle = VisualizerHelpers.rgba(frameData.accent, 0.18 + highs * 0.12)
      canvas.lineWidth = 4.6; canvas.beginPath()
      for (var p = 0; p < points.length; p++) {
        if (p === 0) canvas.moveTo(points[p].x, points[p].y)
        else canvas.lineTo(points[p].x, points[p].y)
      }
      canvas.stroke()
    }
    renderTrail(canvas, frameData, animationState.warpTrails[trail], freshness, highs, animationState.warpImpulse)
  }
  renderBeads(canvas, frameData, points, animationState.warpImpulse)
}

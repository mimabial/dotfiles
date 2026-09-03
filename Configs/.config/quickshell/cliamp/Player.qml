pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

import "visualizers/bars.js" as VisBars
import "visualizers/bricks.js" as VisBricks
import "visualizers/columns.js" as VisColumns
import "visualizers/classic_led.js" as VisClassicLED
import "visualizers/peaks.js" as VisPeaks
import "visualizers/stereo.js" as VisStereo
import "visualizers/correlation.js" as VisCorrelation
import "visualizers/ascii.js" as VisAscii
import "visualizers/wave.js" as VisWave
import "visualizers/scope.js" as VisScope
import "visualizers/sine.js" as VisSine
import "visualizers/heartbeat.js" as VisHeartbeat
import "visualizers/siriwave.js" as VisSiriWave
import "visualizers/soundcloud_wave.js" as VisSoundCloudWave
import "visualizers/telegram_wave.js" as VisTelegramWave
import "visualizers/daw_wave.js" as VisDAWWave
import "visualizers/led_scrubber.js" as VisLEDScrubber
import "visualizers/heatmap_wave.js" as VisHeatmapWave
import "visualizers/grounded_wave.js" as VisGroundedWave
import "visualizers/retro.js" as VisRetro
import "visualizers/matrix.js" as VisMatrix
import "visualizers/binary.js" as VisBinary
import "visualizers/terrain.js" as VisTerrain
import "visualizers/mosaic.js" as VisMosaic
import "visualizers/scatter.js" as VisScatter
import "visualizers/butterfly.js" as VisButterfly
import "visualizers/plasma.js" as VisPlasma
import "visualizers/osc_warp.js" as VisOscWarp
import "visualizers/crt_scanline.js" as VisCRTScanline
import "visualizers/cyber_tunnel.js" as VisCyberTunnel
import "visualizers/background.js" as VisBackground
import "visualizers/helpers.js" as VisTheme

// HUD header + visualizer canvas + seek bar
Item {
  id: root
  property var p  // Panel root

  width: parent ? parent.width : 0
  implicitHeight: hud.implicitHeight + Style.space(12)

  property bool lyricsVisible: false
  property var lyricsLines: []
  property int lyricsCurrentIdx: -1
  property string lyricsTrack: ""

  property real beatDropPulse: 0.0
  property real _bassAvg: 0.0
  property double _lastDropTime: 0
  property double _lastBeatTime: 0
  readonly property var scrubberShape: makeScrubberShape(root.p
    ? root.p.currentUrl + "\0" + root.p.currentArtist + "\0" + root.p.currentTrack : "")

  function makeScrubberShape(key) {
    var seed = 2166136261, values = [], level = 0.5
    for (var i = 0; i < key.length; i++) seed = Math.imul(seed ^ key.charCodeAt(i), 16777619)
    for (var j = 0; j < 54; j++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) | 0
      level = level * 0.35 + ((seed >>> 0) / 4294967295) * 0.65
      values.push((0.7 + Math.sin(Math.PI * (j + 0.5) / 54) * 0.3) * level)
    }
    return values
  }

  // Time constants are in seconds and applied against measured dt, so the detector
  // behaves the same whether the spectrum arrives at 23 or 47 frames per second.
  readonly property real _bassTau: 0.263
  readonly property real _pulseTau: 0.334

  function updateBeatDrop() {
    var bands = root.p ? root.p.visBandsRaw : null
    if (!bands || bands.length < 3 || !root.p.isPlaying) {
      beatDropPulse = 0.0
      _lastBeatTime = 0
      return
    }
    var now = Date.now()
    var dt = _lastBeatTime > 0 ? Math.min(0.2, (now - _lastBeatTime) / 1000.0) : 0.043
    _lastBeatTime = now

    var subBass = (bands[0] + bands[1] + bands[2]) / 3.0
    var avg = _bassAvg + (subBass - _bassAvg) * (1.0 - Math.exp(-dt / _bassTau))
    _bassAvg = avg
    var delta = subBass - avg
    // Tuned against 30s of live capture at 108 BPM: delta 0.15 is what puts the median
    // inter-onset interval at exactly one beat. subBass is only a quiet-passage gate --
    // it never binds on loud material, so it sits low to stay useful on quiet tracks.
    if (subBass > 0.30 && delta > 0.15 && (now - _lastDropTime) > 260) {
      beatDropPulse = 1.0
      _lastDropTime = now
    } else {
      beatDropPulse = Math.max(0.0, beatDropPulse * Math.exp(-dt / _pulseTau) - 0.47 * dt)
    }
  }

  function toggleLyrics() {
    lyricsVisible = !lyricsVisible
    if (lyricsVisible && (lyricsLines.length === 0 || lyricsTrack !== root.p.currentTrack)) {
      fetchLyrics()
    }
  }

  function fetchLyrics() {
    lyricsLines = []
    lyricsCurrentIdx = -1
    lyricsTrack = root.p.currentTrack
    lyricsProc.running = false
    lyricsProc.command = ["python3", Qt.resolvedUrl("cliamp_ctl.py").toString().replace("file://", ""), "lyrics", root.p.currentTrack, root.p.currentArtist, root.p.currentUrl]
    lyricsProc.running = true
  }

  function parseLyrics(raw) {
    if (!raw || typeof raw !== "string") {
      lyricsLines = []
      return
    }
    var lines = []
    var rawLines = raw.split("\n")
    var timeRe = /\[(\d{1,3}):(\d{1,2}(?:\.\d+)?)\]/g
    for (var i = 0; i < rawLines.length; i++) {
      var l = rawLines[i].trim()
      if (!l) continue
      if (/^\[(ar|ti|al|by|offset|length|re|ve):/i.test(l)) continue
      var match
      var times = []
      var textStart = 0
      timeRe.lastIndex = 0
      while ((match = timeRe.exec(l)) !== null) {
        var min = parseInt(match[1])
        var sec = parseFloat(match[2])
        times.push(min * 60 + sec)
        textStart = timeRe.lastIndex
      }
      var lineText = l.slice(textStart).trim()
      if (times.length > 0) {
        for (var t = 0; t < times.length; t++) {
          lines.push({ time: times[t], text: lineText })
        }
      } else if (lineText && !/^\[.*?\]$/.test(lineText)) {
        lines.push({ time: -1, text: lineText })
      }
    }
    lines.sort(function(a, b) { return a.time - b.time })
    lyricsLines = lines
    updateLyricsPosition(root.p.curSecs)
  }

  function updateLyricsPosition(sec) {
    if (!lyricsVisible || !lyricsLines || !lyricsLines.length) return
    var idx = -1
    for (var i = 0; i < lyricsLines.length; i++) {
      if (lyricsLines[i].time >= 0 && lyricsLines[i].time <= (sec + 0.10)) {
        idx = i
      } else if (lyricsLines[i].time > (sec + 0.10)) {
        break
      }
    }
    if (idx !== lyricsCurrentIdx) {
      lyricsCurrentIdx = idx
    }
  }

  readonly property var _renderers: ({
    "bars": VisBars.render, "bricks": VisBricks.render, "columns": VisColumns.render,
    "classic_led": VisClassicLED.render,
    "peaks": VisPeaks.render, "stereo": VisStereo.render,
    "correlation": VisCorrelation.render, "ascii": VisAscii.render,
    "wave": VisWave.render, "scope": VisScope.render, "sine": VisSine.render,
    "heartbeat": VisHeartbeat.render, "siriwave": VisSiriWave.render,
    "soundcloud_wave": VisSoundCloudWave.render, "telegram_wave": VisTelegramWave.render,
    "daw_wave": VisDAWWave.render, "led_scrubber": VisLEDScrubber.render,
    "heatmap_wave": VisHeatmapWave.render, "grounded_wave": VisGroundedWave.render,
    "retro": VisRetro.render,
    "matrix": VisMatrix.render, "binary": VisBinary.render, "terrain": VisTerrain.render,
    "mosaic": VisMosaic.render, "scatter": VisScatter.render,
    "butterfly": VisButterfly.render, "plasma": VisPlasma.render,
    "osc_warp": VisOscWarp.render, "crt_scanline": VisCRTScanline.render,
    "cyber_tunnel": VisCyberTunnel.render
  })

  readonly property var _modeLabels: ({
    "bars": "Bars", "bricks": "Bricks", "columns": "Columns", "classic_led": "Classic LED",
    "peaks": "Peaks", "stereo": "Stereo", "correlation": "Correlation", "ascii": "Ascii",
    "wave": "Wave", "scope": "Scope", "sine": "Sine Wave",
    "heartbeat": "Heartbeat", "siriwave": "Siri Wave",
    "soundcloud_wave": "SoundCloud Wave", "telegram_wave": "Telegram Wave",
    "daw_wave": "DAW Meter", "led_scrubber": "LED Scrubber",
    "heatmap_wave": "Heatmap Wave", "grounded_wave": "Baseline Wave",
    "retro": "Retro",
    "matrix": "Matrix", "binary": "Binary", "terrain": "Terrain",
    "mosaic": "Mosaic", "scatter": "Scatter",
    "butterfly": "Butterfly", "plasma": "Liquid Plasma",
    "osc_warp": "Oscilloscope Warp", "crt_scanline": "CRT Radar Scope",
    "cyber_tunnel": "3D Cyber Tunnel"
  })

  // dim is foreground at 55% alpha, and helpers.js reads RGB only. Flatten it against
  // the surface here or dim and foreground reach the visualizers as the same colour,
  // which collapses specColor's ramp into a palindrome.
  readonly property color visDim: root.p ? Qt.rgba(
    root.p.surface.r + (root.p.dim.r - root.p.surface.r) * root.p.dim.a,
    root.p.surface.g + (root.p.dim.g - root.p.surface.g) * root.p.dim.a,
    root.p.surface.b + (root.p.dim.b - root.p.surface.b) * root.p.dim.a, 1.0) : "#808080"

  // The theme's own 16 terminal colours. Real designer-picked hues beat anything
  // synthesised from the accent, and they retrack the palette like every other role.
  readonly property var visColors: {
    if (!root.p) return []
    var out = []
    for (var i = 0; i < 16; i++) out.push(root.p.shell.role("c" + i, root.p.dynamicAccent))
    return out
  }

  function requestPaint() { if (visCanvas) visCanvas.requestPaint() }

  BorderSurface {
    id: hud
    width: parent.width
    implicitHeight: col.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: "transparent"
    borderSpec: Border.none()

    Column {
      id: col
      width: parent.width - Style.space(16)
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Brand + LED Timer
      Item {
        width: parent.width
        implicitHeight: Style.space(18)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Row {
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: Style.space(6); height: Style.space(6); radius: width / 2
              color: root.p.isPlaying ? root.p.success : (root.p.isRunning ? root.p.warning : root.p.urgent)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "CLIAMP"
              color: Color.accent
              font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
              font.bold: true; font.letterSpacing: 1
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.p.timeCurrent + " / " + root.p.timeTotal
            color: root.p.isPlaying ? root.p.success : root.p.dim
            font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
          }
        }

        Text {
          id: lyricsIcon
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: "\uf10d"
          color: root.lyricsVisible ? Color.accent : (lyricsMouse.containsMouse ? Color.accent : root.p.dim)
          font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
          MouseArea {
            id: lyricsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleLyrics()
            onContainsMouseChanged: lyricsTip.visible = containsMouse
          }
        }

        Text {
          id: speedIcon
          anchors.right: lyricsIcon.left; anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: root.p.playbackSpeed !== 1.0 ? root.p.playbackSpeed + "x" : "\uf04e"
          color: root.p.playbackSpeed !== 1.0 ? Color.accent : (speedMouse.containsMouse ? Color.accent : root.p.dim)
          font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8; font.bold: root.p.playbackSpeed !== 1.0
          MouseArea {
            id: speedMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.p.cycleSpeed()
            onContainsMouseChanged: speedTip.visible = containsMouse
          }
        }

        Text {
          id: eqIcon
          anchors.right: speedIcon.left; anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: (root.p.eqText && root.p.eqText !== "Flat") ? root.p.eqText : "EQ"
          color: (root.p.eqText && root.p.eqText !== "Flat") || root.p.eqPickerOpen ? Color.accent : (eqMouse.containsMouse ? Color.accent : root.p.dim)
          font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8; font.bold: (root.p.eqText && root.p.eqText !== "Flat") || root.p.eqPickerOpen
          MouseArea {
            id: eqMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.p.eqPickerOpen = !root.p.eqPickerOpen
              if (root.p.eqPickerOpen) {
                root.p.visPickerOpen = false
                root.lyricsVisible = false
              }
            }
            onContainsMouseChanged: eqTip.visible = containsMouse
          }
        }
      }

      // Now Playing Info (Thumbnail + Title + Artist)
      Row {
        width: parent.width
        spacing: Style.space(8)

        BorderSurface {
          width: Style.space(36); height: Style.space(36)
          radius: Style.cornerRadius
          color: root.p.surface
          borderSpec: Border.flat(root.p.isPlaying ? root.p.shell.alpha(root.p.dynamicAccent, 0.5) : root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.25), 1)
          anchors.verticalCenter: parent.verticalCenter

          Image {
            anchors.fill: parent; anchors.margins: 1
            visible: root.p.artPath !== ""
            source: root.p.artSource(root.p.artPath)
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 72; sourceSize.height: 72
          }

          Text {
            anchors.centerIn: parent
            visible: root.p.artPath === ""
            text: "\uf001"
            color: root.p.dynamicAccent
            font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
          }
        }

        Column {
          width: parent.width - Style.space(46)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Item {
            id: titleClip
            width: parent.width
            implicitHeight: titleText1.implicitHeight
            clip: true

            readonly property string fullTitle: {
              if (!root.p.isRunning) return "Daemon idle — click play to start"
              return root.p.currentTrack || "No track loaded"
            }

            Item {
              id: titleScroller
              height: parent.height
              width: titleText1.implicitWidth + (titleText1.implicitWidth > titleClip.width ? Style.space(40) + titleText2.implicitWidth : 0)

              readonly property bool needsScroll: titleText1.implicitWidth > titleClip.width
              readonly property real loopDistance: titleText1.implicitWidth + Style.space(40)

              NumberAnimation on x {
                running: titleScroller.needsScroll && root.p.isPlaying
                loops: Animation.Infinite
                from: 0
                to: -titleScroller.loopDistance
                duration: Math.max(2500, titleScroller.loopDistance * 32)
              }

              Row {
                spacing: Style.space(40)

                Text {
                  id: titleText1
                  textFormat: Text.PlainText
                  text: titleClip.fullTitle
                  color: root.p.isPlaying ? root.p.dynamicAccent : root.p.foreground
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  id: titleText2
                  visible: titleScroller.needsScroll
                  textFormat: Text.PlainText
                  text: titleClip.fullTitle
                  color: root.p.isPlaying ? root.p.dynamicAccent : root.p.foreground
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              onNeedsScrollChanged: { if (!needsScroll) x = 0 }
            }
          }

          Item {
            id: artistClip
            width: parent.width
            implicitHeight: artistText1.implicitHeight
            clip: true

            Item {
              id: artistScroller
              height: parent.height
              width: artistText1.implicitWidth + (artistText1.implicitWidth > artistClip.width ? Style.space(40) + artistText2.implicitWidth : 0)

              readonly property bool needsScroll: artistText1.implicitWidth > artistClip.width
              readonly property real loopDistance: artistText1.implicitWidth + Style.space(40)

              NumberAnimation on x {
                running: artistScroller.needsScroll && root.p.isPlaying
                loops: Animation.Infinite
                from: 0
                to: -artistScroller.loopDistance
                duration: Math.max(2500, artistScroller.loopDistance * 35)
              }

              Row {
                spacing: Style.space(40)

                Text {
                  id: artistText1
                  textFormat: Text.PlainText
                  text: root.p ? root.p.currentArtist : ""
                  color: root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }

                Text {
                  id: artistText2
                  visible: artistScroller.needsScroll
                  textFormat: Text.PlainText
                  text: root.p ? root.p.currentArtist : ""
                  color: root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }
              }

              onNeedsScrollChanged: { if (!needsScroll) x = 0 }
            }
          }
        }
      }

      // Visualizer Canvas Frame
      BorderSurface {
        width: parent.width
        height: Style.space(52)
        radius: Style.cornerRadius
        clip: true
        color: root.p.surface
        borderSpec: Border.flat(root.p.isPlaying ? root.p.shell.alpha(root.p.dynamicAccent, 0.7) : root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.3), 1)

        Canvas {
          id: visCanvas
          anchors.fill: parent
          anchors.margins: Style.space(3)
          z: 4

          Connections {
            target: root.p
            function onDynamicAccentChanged() { visCanvas.requestPaint() }
            function onForegroundChanged() { visCanvas.requestPaint() }
            function onDimChanged() { visCanvas.requestPaint() }
            function onSurfaceChanged() { visCanvas.requestPaint() }
          }

          onPaint: {
            root.updateBeatDrop()
            var ctx = getContext("2d")
            var w = width, h = height
            ctx.clearRect(0, 0, w, h)

            var count = 24, gap = 3
            var barW = Math.floor((w - (count - 1) * gap) / count)
            var payload = {
              bands: root.p.visBands, bandsDb: root.p.visBandsDb, bandEdges: root.p.visBandEdges,
              rawBands: root.p.visBandsRaw, bandsStereo: root.p.visBandsStereo,
              wave: root.p.visWave, waveStereo: root.p.visWaveStereo, stereo: root.p.visStereo,
              analysis: root.p.visAnalysis, frame: root.p.visFrame,
              playing: root.p.isPlaying, width: w, height: h, S: 2,
              count: count, barW: barW, gap: gap,
              accent: root.p.dynamicAccent, foreground: root.p.foreground, dim: root.visDim,
              surface: root.p.surface, colors: root.visColors,
              beatDrop: root.beatDropPulse, progress: root.p.progress,
              state: root.p._visState
            }

            if (root.p.visBackground) VisBackground.render(ctx, payload)

            var fn = root._renderers[root.p.visMode]
            if (fn) fn(ctx, payload)
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              root.p.visPickerOpen = !root.p.visPickerOpen
              if (root.p.visPickerOpen && root.lyricsVisible) root.lyricsVisible = false
            } else {
              var idx = root.p.visModes.indexOf(root.p.visMode)
              root.p.setVisMode(root.p.visModes[(idx + 1) % root.p.visModes.length])
            }
          }
        }

        Rectangle {
          anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.margins: Style.space(3)
          width: modeText.implicitWidth + Style.space(10); height: Style.space(16)
          radius: Style.cornerRadius
          color: root.p.visPickerOpen ? Color.menu.selectedBackground
            : (modeMouse.containsMouse ? root.p.shell.hoverFill(1) : root.p.shell.alpha(root.p.surface, 0.75))

          Text {
            id: modeText
            anchors.centerIn: parent
            text: (root._modeLabels[root.p.visMode] || root.p.visMode) + " ▾"
            color: root.p.visPickerOpen ? Color.menu.selectedText
              : (modeMouse.containsMouse ? root.p.shell.role("hvr_fg", Color.accent) : root.p.shell.alpha(root.p.foreground, 0.8))
            font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.75; font.bold: true
          }

          MouseArea {
            id: modeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.p.visPickerOpen = !root.p.visPickerOpen
              if (root.p.visPickerOpen && root.lyricsVisible) root.lyricsVisible = false
            }
          }
        }
      }

      // Waveform Scrubber (SoundCloud / WaveformScrubber style with dual-color played tint and playhead needle)
      Item {
        id: seekBar
        width: parent.width
        implicitHeight: Style.space(18)
        property int hoverSecs: -1

        Canvas {
          id: waveScrubberCanvas
          anchors.fill: parent
          anchors.margins: Style.space(1)
          property var shape: root.scrubberShape
          property bool randomShape: !!(root.p && root.p.randomizeProgressShape)
          onShapeChanged: requestPaint()
          onRandomShapeChanged: requestPaint()

          Connections {
            target: root.p
            function onProgressChanged() { waveScrubberCanvas.requestPaint() }
            function onDynamicAccentChanged() { waveScrubberCanvas.requestPaint() }
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var count = 54
            var gap = 2
            var barW = Math.max(2, Math.floor((width - (count - 1) * gap) / count))
            var totalW = count * barW + (count - 1) * gap
            var startX = Math.floor((width - totalW) / 2)
            var midY = height / 2.0
            var playX = width * root.p.progress

            for (var i = 0; i < count; i++) {
              var bx = startX + i * (barW + gap)
              var barCenter = bx + barW / 2.0
              var isPlayed = barCenter <= playX
              var barH = barW + (height - barW) * (waveScrubberCanvas.randomShape ? waveScrubberCanvas.shape[i] : 0)
              var r = barW / 2.0
              var by = midY - barH / 2.0

              if (isPlayed) {
                var grad = ctx.createLinearGradient(0, by, 0, by + barH)
                grad.addColorStop(0, VisTheme.rgba(root.p.foreground, 0.95))
                grad.addColorStop(0.4, VisTheme.rgba(root.p.dynamicAccent, 0.95))
                grad.addColorStop(1, VisTheme.mixColor(root.p.dynamicAccent, root.p.surface, 0.3, 0.8))
                ctx.fillStyle = grad
              } else {
                ctx.fillStyle = VisTheme.rgba(root.p.foreground, 0.18)
              }

              ctx.beginPath()
              VisTheme.roundedRect(ctx, bx, by, barW, barH, r)
              ctx.fill()
            }

            // Playhead Cursor Needle
            if (root.p.totalSecs > 0) {
              var curX = Math.max(1, Math.min(width - 1, playX))
              ctx.fillStyle = VisTheme.rgba(root.p.foreground, 1)
              ctx.beginPath()
              ctx.rect(curX - 1, 0, 2, height)
              ctx.fill()
            }
          }
        }

        // Hover time tooltip
        Text {
          visible: seekBar.hoverSecs >= 0 && root.p.totalSecs > 0
          text: {
            var s = seekBar.hoverSecs
            var m = Math.floor(s / 60), sec = s % 60
            return m + ":" + (sec < 10 ? "0" + sec : sec)
          }
          color: root.p.foreground; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
          x: Math.max(0, Math.min(parent.width - width, seekMouse.mouseX - width / 2))
          y: -height - 4

          Rectangle {
            z: -1; anchors.fill: parent; anchors.margins: -2
            radius: Style.space(2); color: root.p.surface
            border.color: Color.accent; border.width: 1
          }
        }

        // Draggable seek area
        MouseArea {
          id: seekMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (root.p.totalSecs > 0) seekBar.hoverSecs = Math.floor((mouse.x / width) * root.p.totalSecs)
            if (pressed && root.p.totalSecs > 0) root.p.seekTo(Math.floor((mouse.x / width) * root.p.totalSecs))
          }
          onExited: seekBar.hoverSecs = -1
          onClicked: function(mouse) {
            if (root.p.totalSecs > 0) root.p.seekTo(Math.floor((mouse.x / width) * root.p.totalSecs))
          }
        }
      }
    }

    Text {
      id: lyricsTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(24)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "Lyrics"; color: Color.accent
      font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }

    Text {
      id: speedTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(48)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "Speed"; color: Color.accent
      font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }

    Text {
      id: eqTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(72)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "EQ: " + (root.p.eqText || "Flat"); color: Color.accent
      font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }
  }

  Process {
    id: lyricsProc
    command: ["python3", Qt.resolvedUrl("cliamp_ctl.py").toString().replace("file://", ""), "lyrics", root.p.currentTrack, root.p.currentArtist]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          if (d.synced) root.parseLyrics(d.synced)
          else if (d.plain) root.parseLyrics(d.plain)
          else root.lyricsLines = []
        } catch (e) { root.lyricsLines = [] }
      }
    }
  }
}

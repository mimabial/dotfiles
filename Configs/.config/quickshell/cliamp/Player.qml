import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

import "visualizers/bars.js" as VisBars
import "visualizers/peaks.js" as VisPeaks
import "visualizers/stereo.js" as VisStereo
import "visualizers/ascii.js" as VisAscii
import "visualizers/siriwave.js" as VisSiriWave
import "visualizers/soundcloud_wave.js" as VisSoundCloudWave
import "visualizers/telegram_wave.js" as VisTelegramWave
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

  function updateBeatDrop() {
    if (!p || !p.visBands || p.visBands.length < 3 || !p.isPlaying) {
      beatDropPulse = 0.0
      return
    }
    var subBass = (p.visBands[0] + p.visBands[1] + p.visBands[2]) / 3.0
    var avg = _bassAvg * 0.85 + subBass * 0.15
    _bassAvg = avg
    var delta = subBass - avg
    var now = Date.now()
    if (subBass > 0.40 && delta > 0.15 && (now - _lastDropTime) > 260) {
      beatDropPulse = 1.0
      _lastDropTime = now
    } else {
      beatDropPulse = Math.max(0.0, beatDropPulse * 0.88 - 0.02)
    }
  }

  function toggleLyrics() {
    lyricsVisible = !lyricsVisible
    if (lyricsVisible && (lyricsLines.length === 0 || lyricsTrack !== p.currentTrack)) {
      fetchLyrics()
    }
  }

  function fetchLyrics() {
    lyricsLines = []
    lyricsCurrentIdx = -1
    lyricsTrack = p.currentTrack
    lyricsProc.running = false
    lyricsProc.command = ["python3", Qt.resolvedUrl("cliamp_ctl.py").toString().replace("file://", ""), "lyrics", p.currentTrack, p.currentArtist, p.currentUrl]
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
    updateLyricsPosition(p.curSecs)
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
    "bars": VisBars.render, "peaks": VisPeaks.render,
    "stereo": VisStereo.render, "ascii": VisAscii.render,
    "siriwave": VisSiriWave.render, "soundcloud_wave": VisSoundCloudWave.render,
    "telegram_wave": VisTelegramWave.render
  })

  readonly property var _modeLabels: ({
    "bars": "Bars", "peaks": "Peaks",
    "stereo": "Stereo", "ascii": "Ascii",
    "siriwave": "Siri Wave", "soundcloud_wave": "SoundCloud Wave",
    "telegram_wave": "Telegram Wave"
  })

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
              color: p.isPlaying ? p.success : (p.isRunning ? p.warning : p.urgent)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "CLIAMP"
              color: Color.accent
              font.family: p.fontFamily; font.pixelSize: Style.font.caption
              font.bold: true; font.letterSpacing: 1
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: p.timeCurrent + " / " + p.timeTotal
            color: p.isPlaying ? p.success : p.dim
            font.family: p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
          }
        }

        Text {
          id: lyricsIcon
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: "\uf10d"
          color: root.lyricsVisible ? Color.accent : (lyricsMouse.containsMouse ? Color.accent : p.dim)
          font.family: p.fontFamily; font.pixelSize: Style.font.caption
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
          text: p.playbackSpeed !== 1.0 ? p.playbackSpeed + "x" : "\uf04e"
          color: p.playbackSpeed !== 1.0 ? Color.accent : (speedMouse.containsMouse ? Color.accent : p.dim)
          font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.8; font.bold: p.playbackSpeed !== 1.0
          MouseArea {
            id: speedMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: p.cycleSpeed()
            onContainsMouseChanged: speedTip.visible = containsMouse
          }
        }

        Text {
          id: eqIcon
          anchors.right: speedIcon.left; anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: (p.eqText && p.eqText !== "Flat") ? p.eqText : "EQ"
          color: (p.eqText && p.eqText !== "Flat") || p.eqPickerOpen ? Color.accent : (eqMouse.containsMouse ? Color.accent : p.dim)
          font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.8; font.bold: (p.eqText && p.eqText !== "Flat") || p.eqPickerOpen
          MouseArea {
            id: eqMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
              p.eqPickerOpen = !p.eqPickerOpen
              if (p.eqPickerOpen) {
                p.visPickerOpen = false
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
          color: p.surface
          borderSpec: Border.flat(p.isPlaying ? p.shell.alpha(p.dynamicAccent, 0.5) : p.shell.alpha(p.shell.role("br", p.foreground), 0.25), 1)
          anchors.verticalCenter: parent.verticalCenter

          Image {
            anchors.fill: parent; anchors.margins: 1
            visible: p.artPath !== ""
            source: p.artSource(p.artPath)
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 72; sourceSize.height: 72
          }

          Text {
            anchors.centerIn: parent
            visible: p.artPath === ""
            text: "\uf001"
            color: p.dynamicAccent
            font.family: p.fontFamily; font.pixelSize: Style.font.caption
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
              if (!p.isRunning) return "Daemon idle — click play to start"
              return p.currentTrack || "No track loaded"
            }

            Item {
              id: titleScroller
              height: parent.height
              width: titleText1.implicitWidth + (titleText1.implicitWidth > titleClip.width ? Style.space(40) + titleText2.implicitWidth : 0)

              readonly property bool needsScroll: titleText1.implicitWidth > titleClip.width
              readonly property real loopDistance: titleText1.implicitWidth + Style.space(40)

              NumberAnimation on x {
                running: titleScroller.needsScroll && p.isPlaying
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
                  color: p.isPlaying ? p.dynamicAccent : p.foreground
                  font.family: p.fontFamily; font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  id: titleText2
                  visible: titleScroller.needsScroll
                  textFormat: Text.PlainText
                  text: titleClip.fullTitle
                  color: p.isPlaying ? p.dynamicAccent : p.foreground
                  font.family: p.fontFamily; font.pixelSize: Style.font.bodySmall
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
                running: artistScroller.needsScroll && p.isPlaying
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
                  text: p ? p.currentArtist : ""
                  color: p.dim
                  font.family: p.fontFamily; font.pixelSize: Style.font.caption
                }

                Text {
                  id: artistText2
                  visible: artistScroller.needsScroll
                  textFormat: Text.PlainText
                  text: p ? p.currentArtist : ""
                  color: p.dim
                  font.family: p.fontFamily; font.pixelSize: Style.font.caption
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
        color: p.surface
        borderSpec: Border.flat(p.isPlaying ? p.shell.alpha(p.dynamicAccent, 0.7) : p.shell.alpha(p.shell.role("br", p.foreground), 0.3), 1)

        Canvas {
          id: visCanvas
          anchors.fill: parent
          anchors.margins: Style.space(3)
          z: 4

          Connections {
            target: p
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

            // ── Visualizer on top ──
            var count = 24, gap = 3
            var barW = Math.floor((w - (count - 1) * gap) / count)
            var fn = root._renderers[p.visMode]
            if (fn) fn(ctx, {
              bands: p.visBands, wave: p.visWave, frame: p.visFrame,
              playing: p.isPlaying, width: w, height: h, S: 2,
              count: count, barW: barW, gap: gap,
              accent: p.dynamicAccent, foreground: p.foreground, dim: p.dim,
              beatDrop: root.beatDropPulse, progress: p.progress,
              state: p._visState
            })
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              p.visPickerOpen = !p.visPickerOpen
              if (p.visPickerOpen && root.lyricsVisible) root.lyricsVisible = false
            } else {
              var idx = p.visModes.indexOf(p.visMode)
              p.setVisMode(p.visModes[(idx + 1) % p.visModes.length])
            }
          }
        }

        Rectangle {
          anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.margins: Style.space(3)
          width: modeText.implicitWidth + Style.space(10); height: Style.space(16)
          radius: Style.cornerRadius
          color: p.visPickerOpen ? Color.menu.selectedBackground
            : (modeMouse.containsMouse ? p.shell.hoverFill(1) : p.shell.alpha(p.surface, 0.75))

          Text {
            id: modeText
            anchors.centerIn: parent
            text: (root._modeLabels[p.visMode] || p.visMode) + " ▾"
            color: p.visPickerOpen ? Color.menu.selectedText
              : (modeMouse.containsMouse ? p.shell.role("hvr_fg", Color.accent) : p.shell.alpha(p.foreground, 0.8))
            font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.75; font.bold: true
          }

          MouseArea {
            id: modeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
              p.visPickerOpen = !p.visPickerOpen
              if (p.visPickerOpen && root.lyricsVisible) root.lyricsVisible = false
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

          Connections {
            target: p
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
            var playX = width * p.progress

            for (var i = 0; i < count; i++) {
              var bx = startX + i * (barW + gap)
              var barCenter = bx + barW / 2.0
              var isPlayed = barCenter <= playX
              var r = barW / 2.0
              var by = midY - r

              if (isPlayed) {
                var grad = ctx.createLinearGradient(0, by, 0, by + barW)
                grad.addColorStop(0, VisTheme.rgba(p.foreground, 0.95))
                grad.addColorStop(0.4, VisTheme.rgba(p.dynamicAccent, 0.95))
                grad.addColorStop(1, VisTheme.mixColor(p.dynamicAccent, p.surface, 0.3, 0.8))
                ctx.fillStyle = grad
              } else {
                ctx.fillStyle = VisTheme.rgba(p.foreground, 0.18)
              }

              ctx.beginPath()
              ctx.arc(bx + r, midY, r, 0, Math.PI * 2)
              ctx.fill()
            }

            // Playhead Cursor Needle
            if (p.totalSecs > 0) {
              var curX = Math.max(1, Math.min(width - 1, playX))
              ctx.fillStyle = VisTheme.rgba(p.foreground, 1)
              ctx.beginPath()
              ctx.rect(curX - 1, 0, 2, height)
              ctx.fill()
            }
          }
        }

        // Hover time tooltip
        Text {
          visible: seekBar.hoverSecs >= 0 && p.totalSecs > 0
          text: {
            var s = seekBar.hoverSecs
            var m = Math.floor(s / 60), sec = s % 60
            return m + ":" + (sec < 10 ? "0" + sec : sec)
          }
          color: p.foreground; font.family: p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
          x: Math.max(0, Math.min(parent.width - width, seekMouse.mouseX - width / 2))
          y: -height - 4

          Rectangle {
            z: -1; anchors.fill: parent; anchors.margins: -2
            radius: Style.space(2); color: p.surface
            border.color: Color.accent; border.width: 1
          }
        }

        // Draggable seek area
        MouseArea {
          id: seekMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (p.totalSecs > 0) seekBar.hoverSecs = Math.floor((mouse.x / width) * p.totalSecs)
            if (pressed && p.totalSecs > 0) p.seekTo(Math.floor((mouse.x / width) * p.totalSecs))
          }
          onExited: seekBar.hoverSecs = -1
          onClicked: function(mouse) {
            if (p.totalSecs > 0) p.seekTo(Math.floor((mouse.x / width) * p.totalSecs))
          }
        }
      }
    }

    Text {
      id: lyricsTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(24)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "Lyrics"; color: Color.accent
      font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }

    Text {
      id: speedTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(48)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "Speed"; color: Color.accent
      font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }

    Text {
      id: eqTip; visible: false
      anchors.right: parent.right; anchors.rightMargin: Style.space(72)
      anchors.top: parent.top; anchors.topMargin: Style.space(2)
      text: "EQ: " + (p.eqText || "Flat"); color: Color.accent
      font.family: p.fontFamily; font.pixelSize: Style.font.caption * 0.7
      z: 9999
    }
  }

  Process {
    id: lyricsProc
    command: ["python3", Qt.resolvedUrl("cliamp_ctl.py").toString().replace("file://", ""), "lyrics", p.currentTrack, p.currentArtist]
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

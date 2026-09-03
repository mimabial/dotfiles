import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui
import "cliamp"

PopupCard {
  id: root
  popupName: "media"
  padding: 0
  surfaceOpacity: 0.94
  borderOpacity: 0.45
  contentWidth: Commons.Style.space(400)
  contentHeight: Math.min(mainColumn.implicitHeight + Commons.Style.space(16), Commons.Style.space(560))
  wantsKeyboard: trackList.urlInput.activeFocus

  readonly property color foreground: shell.foreground
  readonly property color urgent: shell.role("error", foreground)
  readonly property color warning: shell.role("warning", Commons.Color.accent)
  readonly property color success: shell.role("success", Commons.Color.accent)
  readonly property color dim: shell.alpha(foreground, 0.55)
  readonly property color surface: shell.role("bg", shell.background)
  readonly property string fontFamily: shell.fontFamily

  // ---- State
  property bool isRunning: false
  property string playbackState: "stopped"
  readonly property bool isPlaying: playbackState === "playing"
  property string currentTrack: "No track loaded"
  property string currentArtist: ""
  property string currentUrl: ""
  property string artPath: ""
  property color dynamicAccent: Commons.Color.accent
  Behavior on dynamicAccent { ColorAnimation { duration: 500; easing.type: Easing.InOutQuad } }
  property string timeCurrent: "00:00"
  property string timeTotal: "00:00"
  property real curSecs: 0.0
  property real totalSecs: 0.0
  property real progress: 0.0
  property bool randomizeProgressShape: false
  property real playbackSpeed: 1.0
  property int volumePct: 80
  property real volumeDb: 0.0
  property bool shuffleMode: false
  property string repeatMode: "off"
  property real _lastStatusTime: 0
  property string eqText: "Custom"
  property var audioFx: ({ "eq": "Flat", "loudnorm": false, "spatial": false })
  property int _preMuteVol: 80

  property var historyList: []
  property var playlistsList: []
  property var queueList: []
  property int queueCount: 0
  property string queueSource: "cliamp"
  property var searchResults: []
  property bool isSearching: false
  property string searchQuery: ""
  property string loadingVid: ""
  property string selectedTab: "history"
  property string urlInputText: ""
  property string visMode: "siriwave"
  property bool visBackground: false
  property bool visPickerOpen: false
  property bool eqPickerOpen: false
  property var visModes: [
    "bars", "bricks", "columns", "classic_led",
    "peaks", "stereo", "correlation", "ascii",
    "wave", "scope", "sine", "heartbeat",
    "siriwave", "soundcloud_wave", "telegram_wave",
    "daw_wave", "led_scrubber", "heatmap_wave", "grounded_wave",
    "retro", "matrix", "binary", "terrain", "mosaic",
    "scatter", "butterfly",
    "plasma", "osc_warp", "crt_scanline", "cyber_tunnel"
  ]

  // Visualizer state
  property var visBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visBandsRaw: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visBandsStereo: ({ "left": [], "right": [] })
  property var visPeaks: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visWave: []
  property var visWaveStereo: ({ "left": [], "right": [] })
  property var visBandsDb: []
  property var visBandEdges: []
  property var visStereo: ({ "levels": [0, 0], "peaks": [0, 0] })
  property var visAnalysis: ({})
  property string _latestSpectrumRaw: ""
  property double _lastSpectrumCapture: 0
  // Animation clock for the visualizers. Wall-clock rather than a per-spectrum-frame
  // counter so d.frame keeps its cadence when the capture hop or repaint rate changes.
  // double, not int: an epoch-derived counter overflows int32 after ~25h of uptime.
  property double visFrame: 0
  readonly property double _visEpoch: Date.now()
  readonly property double _visTick: 42.7
  property var _visState: ({})
  property var resumeInfo: null
  property bool resumeVisible: false
  property var activePlaylist: null
  property bool isImportingPl: false
  property string plImportError: ""
  readonly property var mprisPlayer: {
    const candidate = Media.player
    return candidate && !root.isCliampPlayer(candidate) ? candidate : null
  }
  readonly property bool externalMedia: mprisPlayer !== null

  function isCliampPlayer(candidate) {
    const key = candidate ? String(candidate.dbusName || candidate.identity || "").toLowerCase() : ""
    return key.includes(".mpv.cliamp") || key === "cliamp"
  }

  function artSource(path) {
    const value = String(path || "").replace("/hqdefault.jpg", "/mqdefault.jpg")
    return value.indexOf("http://") === 0 || value.indexOf("https://") === 0 || value.indexOf("file://") === 0
      ? value : (value ? "file://" + value : "")
  }

  function syncMpris() {
    const p = root.mprisPlayer
    if (!p) return false
    const metadata = p.metadata || ({})
    const newTrack = String(p.trackTitle || "No track loaded")
    const newArtist = Media.displayArtist(p)
    const newUrl = String(metadata["xesam:url"] || "")
    const trackChanged = newTrack !== root.currentTrack || newUrl !== root.currentUrl
    root.isRunning = true
    root.playbackState = p.playbackState === MprisPlaybackState.Playing ? "playing"
      : p.playbackState === MprisPlaybackState.Paused ? "paused" : "stopped"
    root.currentTrack = newTrack
    root.currentArtist = newArtist
    root.currentUrl = newUrl
    root.artPath = String(p.trackArtUrl || "")
    root.totalSecs = p.lengthSupported ? Number(p.length || 0) : 0
    root.timeTotal = Media.time(root.totalSecs)
    root.playbackSpeed = Number(p.rate || 1)
    if (p.volumeSupported) root.volumePct = Math.round(Number(p.volume || 0) * 100)
    root.shuffleMode = p.shuffleSupported ? p.shuffle : false
    root.repeatMode = !p.loopSupported || p.loopState === MprisLoopState.None ? "off"
      : p.loopState === MprisLoopState.Track ? "track" : "all"
    if (trackChanged || !p.positionSupported) root.applyMprisPosition(0)
    root.requestMprisPosition()
    root.resumeVisible = false
    if (trackChanged && newTrack !== "No track loaded") {
      recentProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""),
        "remember", newTrack, newArtist, newUrl || (newTrack + " " + newArtist)]
      recentProc.running = true
    }
    if (trackChanged && root.open && root.selectedTab === "queue") root.loadQueue()
    if (trackChanged && root.open) root.startSpectrum()
    if (trackChanged && playerComp.lyricsVisible && playerComp.lyricsTrack !== newTrack)
      playerComp.fetchLyrics()
    if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
    return true
  }

  function applyMprisPosition(seconds) {
    const value = Number(seconds)
    if (!Number.isFinite(value)) return
    root.curSecs = Math.max(0, root.totalSecs > 0 ? Math.min(value, root.totalSecs) : value)
    root.progress = root.totalSecs > 0 ? root.curSecs / root.totalSecs : 0
    root.timeCurrent = Media.time(root.curSecs)
    root._lastStatusTime = Date.now()
    if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
  }

  function requestMprisPosition() {
    const p = root.mprisPlayer
    if (!p || !p.positionSupported || mprisPositionProc.running) return
    const service = String(p.dbusName || "")
    if (!service) {
      root.applyMprisPosition(p.position)
      return
    }
    mprisPositionProc.source = service
    mprisPositionProc.command = ["busctl", "--user", "--json=short", "get-property", service,
      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"]
    mprisPositionProc.running = true
  }

  onMprisPlayerChanged: {
    if (!root.syncMpris()) root.refresh()
    if (root.open) root.startSpectrum()
  }

  onOpenChanged: {
    if (open) {
      // Pre-warm mpv so it's ready before the user clicks a song.
      // This eliminates cold-start delay after reboot.
      if (!root.externalMedia && !root.isRunning) warmupProc.running = true
      if (!root.syncMpris()) root.refresh()
      loadHistory()
      loadPlaylists()
      loadQueue()
      startSpectrum()
    } else {
      stopSpectrum()
      root.visPickerOpen = false
      root.eqPickerOpen = false
    }
  }

  // ---- Lifecycle
  Component.onCompleted: {
    Commons.Style.shell = root.shell
    Commons.Color.shell = root.shell
    loadPlaylists()
    loadHistory()
    loadQueue()
  }

  function spectrumSelectors() {
    const player = root.mprisPlayer
    if (!player) return ["cliamp", "mpv"]
    const candidates = [Media.playerKey(player), player.dbusName, player.desktopEntry, player.identity,
      player.trackTitle, Media.displayArtist(player)]
    const selectors = []
    for (var i = 0; i < candidates.length; i++) {
      const value = String(candidates[i] || "").trim()
      if (value && selectors.indexOf(value) === -1) selectors.push(value)
    }
    return selectors
  }

  function startSpectrum() {
    spectrumProc.running = false
    spectrumProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "start_spectrum"].concat(spectrumSelectors())
    spectrumProc.running = true
  }

  function stopSpectrum() {
    spectrumProc.running = false
    spectrumProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "stop_spectrum"]
    spectrumProc.running = true
  }

  function showPopup() { root.shell.popupName = "media" }
  function hidePopup() { root.shell.closePopup() }
  function togglePopup() {
    if (root.open) root.hidePopup()
    else root.showPopup()
  }

  function handleKey(event) {
    if (trackList.urlInput.activeFocus) {
      if (event.key === Qt.Key_Escape) {
        trackList.urlInput.focus = false
        return true
      }
      return false
    }
    if (event.key === Qt.Key_Escape) {
      if (root.eqPickerOpen) root.eqPickerOpen = false
      else if (root.visPickerOpen) root.visPickerOpen = false
      else if (playerComp.lyricsVisible) playerComp.toggleLyrics()
      else root.hidePopup()
      return true
    }
    if (event.key === Qt.Key_Space) { root.togglePlayback(); return true }
    if (event.key === Qt.Key_Up) { root.adjustVolume(5); return true }
    if (event.key === Qt.Key_Down) { root.adjustVolume(-5); return true }
    if (event.key === Qt.Key_Right) { root.seekTo(Math.min(root.totalSecs, root.curSecs + 5)); return true }
    if (event.key === Qt.Key_Left) { root.seekTo(Math.max(0, root.curSecs - 5)); return true }
    if (event.text === "/") {
      trackList.urlInput.forceActiveFocus()
      trackList.urlInput.selectAll()
      return true
    }
    if (event.text.toLowerCase() === "m") { root.toggleMute(); return true }
    return root.defaultKey(event)
  }

  // ---- Actions
  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function togglePlayback() {
    const p = root.mprisPlayer
    if (p) {
      if (p.isPlaying && p.canPause) p.pause()
      else if (!p.isPlaying && p.canPlay) p.play()
      else if (p.canTogglePlaying) p.togglePlaying()
      Media.select(p)
      root.syncMpris()
      return
    }
    root.playbackState = (root.playbackState === "playing") ? "paused" : "playing"
    runCmd(["toggle"])
  }
  function play() {
    const p = root.mprisPlayer
    if (p) { if (p.canPlay) p.play(); Media.select(p); root.syncMpris(); return }
    root.playbackState = "playing"
    runCmd(["play"])
  }
  function pause() {
    const p = root.mprisPlayer
    if (p) { if (p.canPause) p.pause(); Media.select(p); root.syncMpris(); return }
    root.playbackState = "paused"
    runCmd(["pause"])
  }
  function stop() {
    const p = root.mprisPlayer
    if (p) { if (p.canControl) p.stop(); Media.select(p); root.syncMpris(); return }
    root.playbackState = "stopped"
    runCmd(["stop"])
  }
  function nextTrack() {
    const p = root.mprisPlayer
    if (p) { if (p.canGoNext) p.next(); Media.select(p); return }
    runCmd(["next"])
  }
  function prevTrack() {
    const p = root.mprisPlayer
    if (p) { if (p.canGoPrevious) p.previous(); Media.select(p); return }
    runCmd(["prev"])
  }
  function toggleShuffle() {
    const p = root.mprisPlayer
    if (p) { if (p.shuffleSupported) p.shuffle = !p.shuffle; return }
    runCmd(["shuffle"])
  }
  function cycleRepeat() {
    const p = root.mprisPlayer
    if (p) {
      if (p.loopSupported) p.loopState = p.loopState === MprisLoopState.None
        ? MprisLoopState.Track : p.loopState === MprisLoopState.Track
          ? MprisLoopState.Playlist : MprisLoopState.None
      return
    }
    runCmd(["repeat"])
  }

  function adjustVolume(delta) {
    setVolume(Math.max(0, Math.min(100, root.volumePct + delta)))
  }

  function setVolume(pct) {
    root.volumePct = pct
    const p = root.mprisPlayer
    if (p) { if (p.volumeSupported) p.volume = pct / 100; return }
    runCmd(["volume_pct", String(pct)])
  }

  function toggleMute() {
    if (root.volumePct > 0) {
      root._preMuteVol = root.volumePct
      setVolume(0)
    } else {
      var target = (root._preMuteVol && root._preMuteVol > 0) ? root._preMuteVol : 80
      setVolume(target)
    }
  }

  function seekTo(sec) {
    const p = root.mprisPlayer
    if (p) {
      if (p.canSeek && p.positionSupported) {
        p.position = sec
        root.applyMprisPosition(sec)
      }
      return
    }
    runCmd(["seek", String(sec)])
  }
  function cycleSpeed() {
    var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var cur = root.playbackSpeed
    var idx = 0
    for (var i = 0; i < speeds.length; i++) { if (Math.abs(speeds[i] - cur) < 0.05) { idx = i; break } }
    var next = speeds[(idx + 1) % speeds.length]
    root.playbackSpeed = next
    const p = root.mprisPlayer
    if (p) { p.rate = Math.max(p.minRate, Math.min(p.maxRate, next)); return }
    runCmd(["speed", String(next)])
  }
  function setEq(preset) {
    root.eqText = preset
    runCmd(["set_eq", preset])
  }
  function setVisMode(mode) {
    if (!mode) return
    root.visMode = mode
    runCmd(["set_vis_mode", mode])
    if (playerComp) playerComp.requestPaint()
  }
  function setVisBackground(enabled) {
    root.visBackground = enabled
    runCmd(["set_vis_bg", enabled ? "1" : "0"])
    if (playerComp) playerComp.requestPaint()
  }
  function toggleLoudnorm() {
    runCmd(["toggle_loudnorm"])
    var next = !(root.audioFx && root.audioFx.loudnorm)
    root.audioFx = { eq: root.eqText, loudnorm: next, spatial: root.audioFx ? root.audioFx.spatial : false }
  }
  function toggleSpatial() {
    runCmd(["toggle_spatial"])
    var next = !(root.audioFx && root.audioFx.spatial)
    root.audioFx = { eq: root.eqText, loudnorm: root.audioFx ? root.audioFx.loudnorm : false, spatial: next }
  }
  function importPlaylist(url, name) {
    if (!url || !url.trim() || root.isImportingPl) return
    root.isImportingPl = true
    root.plImportError = ""
    root.selectedTab = "playlists"
    root.activePlaylist = null
    importPlProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "import_playlist", url.trim(), name || ""]
    importPlProc.running = true
  }

  function deletePlaylist(name) {
    if (!name) return
    if (root.activePlaylist && root.activePlaylist.name === name) {
      root.activePlaylist = null
    }
    runCmd(["delete_playlist", name])
    Qt.callLater(loadPlaylists)
  }

  function openPlaylist(pl) {
    if (!pl) return
    if (pl.system || pl.name === "Recently Played") {
      var recents = []
      for (var i = 0; i < root.historyList.length; i++) {
        var h = root.historyList[i]
        recents.push({
          title: h.title || "Track",
          artist: h.artist || "",
          duration: h.duration_secs ? (Math.floor(h.duration_secs / 60) + ":" + (h.duration_secs % 60 < 10 ? "0" + (h.duration_secs % 60) : (h.duration_secs % 60))) : "",
          url: h.path || (h.title + " " + h.artist)
        })
      }
      root.activePlaylist = { name: "Recently Played", tracks: recents, system: true }
    } else {
      root.activePlaylist = pl
    }
  }

  function closePlaylist() {
    root.activePlaylist = null
  }

  function doResume() { runCmd(["resume"]); root.resumeVisible = false; root.loadingVid = "" }

  function playUrl(url, title, artist) {
    if (!url || !url.trim()) return
    const active = root.mprisPlayer
    if (active && active.isPlaying && active.canPause) active.pause()
    var u = url.trim()
    root.loadingVid = u
    root.currentTrack = title || "Buffering..."
    root.currentArtist = artist || ""
    root.playbackState = "buffering"
    runCmd(["play_item", u, title || "", artist || ""])
    root.urlInputText = ""
  }

  function queueUrl(url, title, artist) {
    if (!url || !url.trim()) return
    runCmd(["queue", url.trim(), title || "", artist || ""])
    root.urlInputText = ""
  }

  function queueContext() {
    const p = root.mprisPlayer
    const key = p ? String(p.dbusName || p.identity || "").toLowerCase() : ""
    if (key.indexOf("mpd") !== -1) return "mpd"
    const url = p ? String((p.metadata || ({ }))["xesam:url"] || "") : ""
    return url.indexOf("list=") !== -1 && (url.indexOf("youtube.com/") !== -1 || url.indexOf("youtu.be/") !== -1) ? url : ""
  }

  function loadQueue() {
    if (queueProc.running) return
    queueProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "queue_list", queueContext()]
    queueProc.running = true
  }

  function displayQueue(source, items) {
    const queue = (items || []).map((item, index) => Object.assign({ queueIndex: index }, item))
    if (source !== "cliamp" || root.playbackState === "stopped" || root.currentTrack === "No track loaded") return queue
    return [{ current: true, queueIndex: -1, url: root.currentUrl, title: root.currentTrack,
      artist: root.currentArtist, thumb: root.artPath }].concat(queue)
  }

  function playQueueItem(item, index) {
    if (item.current === true) { togglePlayback(); return }
    if (item.backend === "mpd") { runCmd(["mpd_play", String(item.position)]); return }
    if (item.backend === "youtube" && root.mprisPlayer) {
      root.mprisPlayer.openUri(item.url); Media.select(root.mprisPlayer); return
    }
    playUrl(item.url, item.title, item.artist)
    removeFromQueue(item.queueIndex === undefined ? index : item.queueIndex)
  }

  function clearQueue() {
    runCmd(["queue_clear"])
  }

  function removeFromQueue(idx) {
    runCmd(["queue_remove", String(idx)])
  }

  function searchTracks(query) {
    if (!query || !query.trim()) return
    var q = query.trim()
    if (q.indexOf("http://") === 0 || q.indexOf("https://") === 0) {
      if (q.indexOf("list=") !== -1 || q.indexOf("/playlist/") !== -1 || q.indexOf("/album/") !== -1) {
        importPlaylist(q)
        root.selectedTab = "playlists"
        return
      }
      playUrl(q)
      return
    }
    root.isSearching = true
    root.searchQuery = q
    root.selectedTab = "search"
    searchProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "search", q]
    searchProc.running = true
  }

  function clearSearch() {
    root.searchQuery = ""
    root.searchResults = []
    root.isSearching = false
    root.selectedTab = "history"
  }

  function playPlaylist(pl) {
    if (!pl || !pl.tracks || pl.tracks.length === 0) return
    var t0 = pl.tracks[0]
    playUrl(t0.url || (t0.title + " " + t0.artist), t0.title, t0.artist)
    for (var i = 1; i < pl.tracks.length; i++) {
      var t = pl.tracks[i]
      queueUrl(t.url || (t.title + " " + t.artist), t.title, t.artist)
    }
  }

  function stopDaemon() {
    runCmd(["stop_daemon"])
    root.isRunning = false
    root.playbackState = "stopped"
  }

  function loadHistory() {
    if (!historyProc.running) historyProc.running = true
  }

  function loadPlaylists() {
    if (!playlistsProc.running) playlistsProc.running = true
  }

  function runCmd(args) {
    actionProc.running = false
    actionProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", "")].concat(args)
    actionProc.running = true
  }

  // ---- Processes
  Process {
    id: mprisPositionProc
    property string source: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const data = JSON.parse(text || "{}")
          const p = root.mprisPlayer
          if (p && String(p.dbusName || "") === mprisPositionProc.source)
            root.applyMprisPosition(Number(data.data) / 1000000)
        } catch (error) {}
      }
    }
  }

  Connections {
    target: root.mprisPlayer
    function onMetadataChanged() { root.syncMpris() }
    function onPlaybackStateChanged() { root.syncMpris() }
    function onPositionChanged() { root.syncMpris() }
    function onLengthChanged() { root.syncMpris() }
    function onVolumeChanged() { root.syncMpris() }
    function onRateChanged() { root.syncMpris() }
  }

  Process {
    id: statusProc
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.syncMpris()) return
        try {
          var data = JSON.parse(text || "{}")
          root.isRunning = data.running === true
          root.playbackState = data.state || "stopped"
          var newTrack = String(data.track || "No track loaded")
          var newUrl = String(data.url || "")
          var trackChanged = (newTrack !== root.currentTrack) || (newUrl !== root.currentUrl)
          root.currentTrack = newTrack
          root.currentArtist = String(data.artist || "")
          root.currentUrl = newUrl
          root.artPath = String(data.art_path || "")
          if (trackChanged && root.open && root.selectedTab === "queue") root.loadQueue()
          if (trackChanged && playerComp.lyricsVisible && playerComp.lyricsTrack !== newTrack) {
            playerComp.fetchLyrics()
          }
          root.timeCurrent = String(data.time_current || "00:00")
          root.timeTotal = String(data.time_total || "00:00")
          root.curSecs = Number(data.cur_secs || 0)
          root._lastStatusTime = Date.now()
          if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
          root.totalSecs = Number(data.total_secs || 0)
          root.progress = Number(data.progress || 0.0)
          root.volumePct = (data.volume_pct !== undefined && data.volume_pct !== null) ? Number(data.volume_pct) : 80
          root.playbackSpeed = Number(data.speed || 1.0)
          root.volumeDb = Number(data.volume_db || 0.0)
          root.shuffleMode = data.shuffle === true
          root.repeatMode = String(data.repeat || "off")
          root.queueCount = (data.queue_count !== undefined) ? Number(data.queue_count) : 0
          root.eqText = String(data.eq || "Custom")
          if (data.audio_fx) root.audioFx = data.audio_fx
          if (data.vis_mode && String(data.vis_mode) !== root.visMode && !root.visPickerOpen) {
            root.visMode = String(data.vis_mode)
          }
          if (data.vis_bg !== undefined && !root.visPickerOpen) {
            root.visBackground = data.vis_bg === true
          }
          if (data.resume && root.playbackState === "stopped") {
            root.resumeInfo = data.resume
            root.resumeVisible = true
          } else {
            root.resumeVisible = false
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: queueProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const data = JSON.parse(text || "{}")
          root.queueSource = data.source || "cliamp"
          root.queueList = root.displayQueue(root.queueSource, data.items)
        } catch (e) { root.queueSource = "cliamp"; root.queueList = [] }
        trackList.queueUpdated()
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.searchResults = JSON.parse(text || "[]") }
        catch (e) { root.searchResults = [] }
        root.isSearching = false
      }
    }
  }

  Process {
    id: historyProc
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "history", "200"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.historyList = JSON.parse(text || "[]") }
        catch (e) { root.historyList = [] }
      }
    }
  }

  Process {
    id: recentProc
    onExited: if (root.open) root.loadHistory()
  }

  Process {
    id: playlistsProc
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "playlists"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.playlistsList = JSON.parse(text || "[]") }
        catch (e) { root.playlistsList = [] }
      }
    }
  }

  Process {
    id: importPlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isImportingPl = false
        try {
          var res = JSON.parse(text || "{}")
          if (res.success) {
            root.plImportError = ""
            loadPlaylists()
          } else {
            root.plImportError = res.error || "Failed to import playlist"
          }
        } catch (e) {
          root.plImportError = "Error importing playlist"
        }
      }
    }
  }

  Process {
    id: actionProc
    onExited: function() {
      root.loadingVid = ""
      root.refresh()
      if (root.open) { loadHistory(); loadQueue() }
      // On cold start (first play after reboot) mpv needs 1-4s to boot + buffer.
      // Poll again at 1s and 3.5s so the UI catches the playing state.
      coldStartTimer.restart()
    }
  }

  Timer {
    id: coldStartTimer
    interval: 1000; repeat: false; running: false
    onTriggered: {
      root.refresh()
      coldStartTimer2.restart()
    }
  }

  Timer {
    id: coldStartTimer2
    interval: 2500; repeat: false; running: false
    onTriggered: root.refresh()
  }

  // Silently pre-warms the mpv daemon when the panel opens.
  // Runs start_daemon which is a no-op if mpv is already running.
  Process {
    id: warmupProc
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "start_daemon"]
    onExited: root.refresh()
  }

  Process {
    id: spectrumProc
  }

  // Poll timer
  Timer {
    id: pollTimer
    interval: root.open ? 500 : 2000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (root.mprisPlayer) root.requestMprisPosition(); else root.refresh()
  }

  readonly property var _xdg: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"
  readonly property string spectrumPath: _xdg + "/cliamp/spectrum.json"

  FileView {
    id: specFile
    path: root.spectrumPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root._latestSpectrumRaw = text()
    onLoadFailed: {}
  }

  function updateSpectrumData(raw) {
    if (!root.open) return
    if (!root.isPlaying) {
      var decayedBands = [], decayedPeaks = [], hasAny = false
      for (var k = 0; k < 24; k++) {
        var b = Math.max(0, (root.visBands[k] || 0) * 0.8 - 0.02)
        var p = Math.max(0, (root.visPeaks[k] || 0) * 0.8 - 0.02)
        decayedBands.push(b); decayedPeaks.push(p)
        if (b > 0 || p > 0) hasAny = true
      }
      root.visBands = decayedBands; root.visPeaks = decayedPeaks
      if (hasAny && playerComp) playerComp.requestPaint()
      return
    }

    var content = raw
    if (!content && specFile) { try { content = specFile.text() } catch (e) {} }
    if (!content) return

    try {
      var data = JSON.parse(content)
      var bands = data.bands || data
      if (Array.isArray(bands) && bands.length >= 24) {
        var analysis = data.analysis || ({})
        var capturedAt = Number(analysis.captured_at_ms || Date.now())
        if (capturedAt === root._lastSpectrumCapture) return
        var spectrumDt = root._lastSpectrumCapture > 0 ? Math.min(0.12, Math.max(0.015, (capturedAt - root._lastSpectrumCapture) / 1000.0)) : root._visTick / 1000.0
        root._lastSpectrumCapture = capturedAt
        var stereoBands = data.bands_stereo || ({}), stereoLeft = stereoBands.left || [], stereoRight = stereoBands.right || []
        var previousStereo = root.visBandsStereo || ({}), previousLeft = previousStereo.left || [], previousRight = previousStereo.right || []
        var newBands = [], newRawBands = [], newPeaks = [], newLeft = [], newRight = []
        for (var i = 0; i < 24; i++) {
          var target = Math.min(1.0, Math.max(0.0, Number(bands[i]) || 0.0))
          var previous = Number(root.visBands[i]) || 0.0
          var tau = target > previous ? 0.075 : 0.23
          var display = previous + (target - previous) * (1.0 - Math.exp(-spectrumDt / tau))
          if (target === 0 && display < 0.001) display = 0
          var prevPeak = root.visPeaks[i] || 0.0
          newRawBands.push(target)
          newBands.push(display)
          newPeaks.push(Math.max(display, prevPeak - 0.38 * spectrumDt))
          var leftTarget = Math.min(1.0, Math.max(0.0, Number(stereoLeft[i]) || 0.0))
          var rightTarget = Math.min(1.0, Math.max(0.0, Number(stereoRight[i]) || 0.0))
          var leftPrevious = Number(previousLeft[i]) || 0.0, rightPrevious = Number(previousRight[i]) || 0.0
          var leftTau = leftTarget > leftPrevious ? 0.075 : 0.23
          var rightTau = rightTarget > rightPrevious ? 0.075 : 0.23
          newLeft.push(leftPrevious + (leftTarget - leftPrevious) * (1.0 - Math.exp(-spectrumDt / leftTau)))
          newRight.push(rightPrevious + (rightTarget - rightPrevious) * (1.0 - Math.exp(-spectrumDt / rightTau)))
        }
        root.visBandsRaw = newRawBands; root.visBands = newBands; root.visPeaks = newPeaks
        root.visBandsStereo = ({ "left": newLeft, "right": newRight })
        root.visWave = Array.isArray(data.wave) ? data.wave : []
        root.visWaveStereo = data.wave_stereo || ({ "left": [], "right": [] })
        root.visBandsDb = Array.isArray(data.bands_dbfs) ? data.bands_dbfs : []
        root.visBandEdges = Array.isArray(data.band_edges_hz) ? data.band_edges_hz : []
        root.visStereo = data.stereo || ({ "levels": [0, 0], "peaks": [0, 0] })
        root.visAnalysis = analysis
        root.visFrame = Math.floor((Date.now() - root._visEpoch) / root._visTick)
        if (playerComp) playerComp.requestPaint()
      }
    } catch (e) {}
  }

  Timer {
    id: visTimer
    interval: Math.round(root._visTick); running: root.open; repeat: true
    onTriggered: {
      if (root.isPlaying) {
        root.updateSpectrumData(root._latestSpectrumRaw)
        specFile.reload()
        if (playerComp && playerComp.lyricsVisible && root._lastStatusTime > 0) {
          var elapsed = (Date.now() - root._lastStatusTime) / 1000.0
          playerComp.updateLyricsPosition(root.curSecs + elapsed * root.playbackSpeed)
        }
      } else {
        root.updateSpectrumData("")
      }
    }
  }

  // IPC
  IpcHandler {
    target: "cliamp"
    function open() { root.showPopup() }
    function close() { root.hidePopup() }
    function show() { root.showPopup() }
    function hide() { root.hidePopup() }
    function toggle() { root.togglePopup() }
    function refresh() { root.refresh() }
    function play() { root.play() }
    function pause() { root.pause() }
    function stop() { root.stop() }
    function next() { root.nextTrack() }
    function prev() { root.prevTrack() }
    function playUrl(url: string) { root.playUrl(url) }
  }

  Column {
        id: mainColumn
        width: parent.width - Commons.Style.space(20)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Commons.Style.space(8)
        topPadding: Commons.Style.space(12)
        bottomPadding: Commons.Style.space(8)

        BorderSurface {
          visible: root.resumeVisible
          width: parent.width; implicitHeight: Commons.Style.space(28)
          radius: Commons.Style.cornerRadius
          color: "transparent"
          borderSpec: Commons.Border.none()

          Row {
            anchors.fill: parent; anchors.margins: Commons.Style.space(6); spacing: Commons.Style.space(6)
            Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf0e2"; color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption }
            Text {
              width: parent.width - Commons.Style.space(80); anchors.verticalCenter: parent.verticalCenter
              text: root.resumeInfo ? "Resume: " + (root.resumeInfo.title || "last track") : ""
              color: root.foreground; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption; elide: Text.ElideRight
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter; text: "Resume"; color: Commons.Color.accent
              font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption; font.bold: true
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.doResume() }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter; text: "\uf00d"; color: root.dim
              font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.resumeVisible = false }
            }
          }
        }

        Player { id: playerComp; p: root }

        Transport { p: root }

        PanelSeparator { foreground: root.foreground }

        TrackList { id: trackList; p: root; visible: !playerComp.lyricsVisible && !root.visPickerOpen && !root.eqPickerOpen }

        // Visualizer Picker (Lazy loaded on demand)
        Loader {
          visible: root.visPickerOpen && !root.eqPickerOpen
          active: root.visPickerOpen
          width: parent.width
          source: "cliamp/VisPicker.qml"
          onLoaded: { if (item) item.p = root }
        }

        // Equalizer Profile Picker (Lazy loaded on demand)
        Loader {
          visible: root.eqPickerOpen
          active: root.eqPickerOpen
          width: parent.width
          source: "cliamp/EqPicker.qml"
          onLoaded: { if (item) item.p = root }
        }

        // Lyrics view — replaces track list when toggled
        Item {
          visible: playerComp.lyricsVisible && !root.visPickerOpen && !root.eqPickerOpen
          width: parent.width
          height: Commons.Style.space(200)

          BorderSurface {
            anchors.fill: parent
            radius: Commons.Style.cornerRadius
            color: "transparent"
            borderSpec: Commons.Border.none()

            Item {
              id: lyricsHeader
              anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
              anchors.margins: Commons.Style.space(8)
              implicitHeight: Commons.Style.space(20)

              Row {
                anchors.left: parent.left
                anchors.right: closeLyricsBtn.left
                anchors.rightMargin: Commons.Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Commons.Style.space(6)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf10d"
                  color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
                }
                Text {
                  width: parent.width - Commons.Style.space(24)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Lyrics — " + (root.currentTrack || "No track")
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
                  font.bold: true; elide: Text.ElideRight
                }
              }

              // Close icon pushed to top far right
              Item {
                id: closeLyricsBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Commons.Style.space(20); height: Commons.Style.space(20)

                Text {
                  anchors.centerIn: parent
                  text: "\uf00d"
                  color: closeLyricsMouse.containsMouse ? Commons.Color.accent : root.dim
                  font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
                }
                MouseArea {
                  id: closeLyricsMouse
                  anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                  onClicked: playerComp.toggleLyrics()
                }
              }
            }

            Text {
              visible: playerComp.lyricsLines.length === 0
              anchors.centerIn: parent
              text: "No synced lyrics available"
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
            }

            ListView {
              id: lyricsList
              visible: playerComp.lyricsLines.length > 0
              anchors.top: lyricsHeader.bottom
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Commons.Style.space(8)
              clip: true
              model: playerComp.lyricsLines
              spacing: Commons.Style.space(6)
              boundsBehavior: Flickable.StopAtBounds

              Connections {
                target: playerComp
                function onLyricsCurrentIdxChanged() {
                  if (playerComp.lyricsCurrentIdx >= 0 && playerComp.lyricsCurrentIdx < playerComp.lyricsLines.length) {
                    lyricsList.positionViewAtIndex(playerComp.lyricsCurrentIdx, ListView.Center)
                  }
                }
              }

              delegate: Item {
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === playerComp.lyricsCurrentIdx
                readonly property bool isPast: playerComp.lyricsCurrentIdx >= 0 && index < playerComp.lyricsCurrentIdx
                width: lyricsList.width
                implicitHeight: lyricText.implicitHeight + Commons.Style.space(4)

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: modelData.time >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    if (modelData.time >= 0) {
                      root.seekTo(modelData.time)
                    }
                  }
                }

                Text {
                  id: lyricText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: modelData.text || "♪"
                  color: isCurrent ? root.dynamicAccent : root.shell.alpha(root.foreground, isPast ? 0.28 : 0.65)
                  font.family: root.fontFamily
                  font.pixelSize: isCurrent ? Commons.Style.font.body : Commons.Style.font.caption
                  font.bold: isCurrent
                  Behavior on color { ColorAnimation { duration: 250 } }
                }
              }
            }
          }
        }
      }
}

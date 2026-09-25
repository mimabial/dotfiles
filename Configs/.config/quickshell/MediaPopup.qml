import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui
import "cliamp"
import "MediaModel.js" as MediaModel

PopupCard {
  id: root
  popupName: "media"
  padding: 0
  surfaceOpacity: 0.94
  borderOpacity: 0.45
  contentWidth: Commons.Style.space(400)
  contentHeight: Math.min(mainColumn.implicitHeight + Commons.Style.space(16), Commons.Style.space(560))
  headerHeight: Commons.Style.space(34)

  readonly property color foreground: shell.foreground
  readonly property color urgent: shell.role("error", foreground)
  readonly property color warning: shell.role("warning", Commons.Color.accent)
  readonly property color success: shell.role("success", Commons.Color.accent)
  readonly property color dim: shell.alpha(foreground, 0.55)
  readonly property color surface: shell.role("bg", shell.background)
  readonly property string fontFamily: shell.fontFamily

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
  // a status read overlapping a command carries pre-command values, and would stamp
  // them back over what the click just set. Bumped on issue and on completion, so a
  // response is only trusted when nothing happened for its whole lifetime.
  property int _commandGen: 0
  property int _statusGen: 0
  property string eqText: "Custom"
  property var audioFx: ({ "eq": "Flat", "loudnorm": false, "spatial": false })
  property int _preMuteVol: 80

  property var historyList: []
  readonly property var historyGroups: MediaModel.historyGroups(root.historyList, Qt.locale())
  property var playlistsList: []
  property var queueItems: []
  property string queueSource: "cliamp"
  // a binding, not a snapshot: displayQueue folds in live playback state, so the
  // list has to re-render when that state lands rather than only on a queue read
  readonly property var queueList: MediaModel.displayQueue(root.queueSource, root.queueItems, {
    state: root.playbackState, title: root.currentTrack, artist: root.currentArtist,
    url: root.currentUrl, art: root.artPath
  })
  // one Process backs runCmd, so a command issued alongside another has to wait
  // for it rather than replace it
  property var pendingCmds: []
  property bool queueReloadPending: false
  // Liked state for every row is read off the Liked playlist, so a row costs no
  // process of its own; overrides carry the optimistic flip until the write lands.
  readonly property bool currentLiked: root.isLiked(root.currentUrl, root.currentTrack, root.currentArtist)
  readonly property var likedIndex: {
    const index = ({})
    for (const pl of root.playlistsList)
      if (pl.name === "Liked")
        for (const track of pl.tracks || []) index[MediaModel.likeKey(track.url, track.title, track.artist)] = true
    return index
  }
  property var likedOverrides: ({})
  property bool _likeDirty: false
  // mpd-mpris owns org.mpris.MediaPlayer2.mpd whenever mpd runs, so the derived
  // context would send every queue read to mpd and hide what "+" just wrote.
  // Adding pins the view to the queue it appended to, until the popup closes.
  property string queueOverride: ""
  // Files tab: one directory of the library at a time, paths relative to its root
  property var filesList: []
  property string filesPath: ""
  property string filesParent: ""
  property bool filesAtRoot: true
  property var searchResults: []
  property bool isSearching: false
  property string searchQuery: ""
  property string loadingVid: ""
  property string selectedTab: "history"
  property string urlInputText: ""
  property string visMode: "osc_warp"
  property bool visBackground: true
  property bool visBackgroundPulse: true
  property bool visPickerOpen: false
  property bool eqPickerOpen: false
  property var visModes: [
    "bars", "bricks", "classic_led",
    "peaks", "stereo", "correlation", "ascii",
    "wave", "sine", "mirror",
    "siriwave", "soundcloud_wave", "telegram_wave",
    "daw_wave", "led_scrubber", "heatmap_wave", "grounded_wave",
    "retro", "matrix", "binary", "terrain", "mosaic",
    "scatter", "rain", "butterfly",
    "plasma", "osc_warp", "crt_scanline", "cyber_tunnel"
  ]

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
  // Dismissal has to outlive the status poll below, which would otherwise raise
  // the banner again a tick later. Keyed by url so a different saved track asks.
  property string resumeDismissedUrl: ""
  property var activePlaylist: null
  property bool isImportingPl: false
  property string plImportError: ""
  readonly property var mprisPlayer: {
    const candidate = Media.player
    return candidate && !MediaModel.isCliampPlayer(candidate) ? candidate : null
  }
  readonly property bool externalMedia: mprisPlayer !== null

  function artSource(path) {
    return MediaModel.artSource(path)
  }

  function syncMpris() {
    const p = root.mprisPlayer
    if (!p) return false
    const metadata = p.metadata || ({})
    const newTrack = String(p.trackTitle || "No track loaded")
    const newArtist = Media.displayArtist(p)
    const newUrl = String(metadata["xesam:url"] || "")
    const trackChanged = newTrack !== root.currentTrack || newArtist !== root.currentArtist || newUrl !== root.currentUrl
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
    const localPath = newUrl.startsWith("file://") ? decodeURIComponent(newUrl.slice(7)) : ""
    if (trackChanged && localPath && newTrack !== "No track loaded") {
      recentProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""),
        "remember", newTrack, newArtist, localPath]
      recentProc.running = true
    }
    if (trackChanged && root.open && root.selectedTab === "queue") root.loadQueue()
    if (trackChanged && root.open) root.startSpectrum()
    if (trackChanged && playerComp.lyricsVisible && playerComp.lyricsTrackKey !== playerComp.lyricsKey())
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
      if (!root.externalMedia && !root.isRunning) warmupProc.running = true
      if (!root.syncMpris()) root.refresh()
      loadHistory()
      loadPlaylists()
      loadQueue()
      loadFiles(root.filesPath)
      startSpectrum()
    } else {
      stopSpectrum()
      root.queueOverride = ""
      root.visPickerOpen = false
      root.eqPickerOpen = false
      // a field left focused reopens mid-edit
      trackList.urlInput.focus = false
    }
  }

  Component.onCompleted: {
    Commons.Style.shell = root.shell
    Commons.Color.shell = root.shell
    root.shell.mediaPopup = root
    refresh()
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
  function showLyrics() {
    if (!playerComp.lyricsVisible) playerComp.toggleLyrics()
    root.showPopup()
  }
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

  function refresh() {
    if (statusProc.running || actionProc.running) return
    root._statusGen = root._commandGen
    statusProc.running = true
  }

  MediaControls { id: mediaControls; controller: root; media: Media }

  function togglePlayback() { mediaControls.togglePlayback() }
  function play() { mediaControls.play() }
  function pause() { mediaControls.pause() }
  function stop() { mediaControls.stop() }
  function nextTrack() { mediaControls.nextTrack() }
  function prevTrack() { mediaControls.prevTrack() }
  function toggleShuffle() { mediaControls.toggleShuffle() }
  function cycleRepeat() { mediaControls.cycleRepeat() }
  function adjustVolume(delta) { mediaControls.adjustVolume(delta) }
  function setVolume(percent) { mediaControls.setVolume(percent) }
  function toggleMute() { mediaControls.toggleMute() }
  function seekTo(seconds) { mediaControls.seekTo(seconds) }
  function cycleSpeed() { mediaControls.cycleSpeed() }
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
  // The track list, both pickers and the lyrics view are mutually exclusive. Route every
  // open through here: setting one flag without clearing the others opens a pane behind
  // another one, and the click reads as dead.
  function showPane(pane) {
    root.visPickerOpen = pane === "vis"
    root.eqPickerOpen = pane === "eq"
    playerComp.lyricsVisible = pane === "lyrics"
  }
  function lyricsAction(action) {
    const store = root.shell.store
    if (action === "refresh") return playerComp.fetchLyrics(true)
    if (action === "close") return playerComp.toggleLyrics()
    if (action === "follow") {
      playerComp.lyricsFollowing = true
      lyricsList.positionViewAtIndex(Math.max(0, playerComp.lyricsCurrentIdx),
        playerComp.lyricsCurrentIdx < 0 ? ListView.Beginning : ListView.Center)
      return
    }
    if (action === "smaller" || action === "larger") {
      store.lyricsFontStep = Math.max(-2, Math.min(4, store.lyricsFontStep + (action === "larger" ? 1 : -1)))
      return
    }
    store.lyricsDelayTenths = action === "reset" ? 0
      : Math.max(-50, Math.min(50, store.lyricsDelayTenths + (action === "later" ? 5 : -5)))
    playerComp.updateLyricsPosition(root.curSecs)
  }
  function setVisBackground(enabled) {
    root.visBackground = enabled
    runCmd(["set_vis_bg", enabled ? "1" : "0"])
    if (playerComp) playerComp.requestPaint()
  }
  function setVisBackgroundPulse(enabled) {
    root.visBackgroundPulse = enabled
    runCmd(["set_vis_bg_pulse", enabled ? "1" : "0"])
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
    if (pl.name === "Recently Played") {
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

  function playUrl(url, title, artist, keepQueue) {
    if (!url || !url.trim()) return
    const active = root.mprisPlayer
    if (active && active.isPlaying && active.canPause) active.pause()
    var u = url.trim()
    root.loadingVid = u
    root.currentTrack = title || "Buffering..."
    root.currentArtist = artist || ""
    root.playbackState = "buffering"
    runCmd([keepQueue ? "play_item" : "play_replace", u, title || "", artist || ""])
    root.urlInputText = ""
  }

  // A row that is showing the live track toggles it, the way playQueueItem does for
  // the queue. Without this the pause glyph reloads the track instead of pausing it.
  function playOrToggle(current, url, title, artist) {
    if (current && root.playbackState !== "stopped") root.togglePlayback()
    else if (url) root.playUrl(url, title, artist)
  }

  function queueUrl(url, title, artist) {
    if (!url || !url.trim()) return
    root.queueOverride = "cliamp"
    runCmd(["queue", url.trim(), title || "", artist || ""])
    root.urlInputText = ""
  }

  function queueDir(rel) {
    root.queueOverride = "cliamp"
    runCmd(["queue_dir", rel || ""])
  }

  function playDir(rel) {
    root.queueOverride = "cliamp"
    root.pendingCmds = []
    root.playbackState = "buffering"
    runCmd(["play_dir", rel || ""])
  }

  function queueContext() {
    return MediaModel.queueContext(root.queueOverride, root.mprisPlayer)
  }

  function loadFiles(rel) {
    if (filesProc.running) return
    filesProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "files", rel || ""]
    filesProc.running = true
  }

  function startQueueLoad() {
    queueProc.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "queue_list", queueContext()]
    queueProc.running = true
  }

  function loadQueue() {
    // dropping the reload leaves the panel showing rows the store no longer has
    if (queueProc.running) { root.queueReloadPending = true; return }
    startQueueLoad()
  }

  function playQueueItem(item, index) {
    if (item.current === true) { togglePlayback(); return }
    if (item.backend === "mpd") { runCmd(["mpd_play", String(item.position)]); return }
    if (item.backend === "youtube" && root.mprisPlayer) {
      root.mprisPlayer.openUri(item.url); Media.select(root.mprisPlayer); return
    }
    if (!item.url || !item.url.trim()) return
    playUrl(item.url, item.title, item.artist, true)
    removeFromQueue(item.queueIndex === undefined ? index : item.queueIndex)
  }

  function clearQueue() {
    // a pending chain of adds would refill the queue the moment this command exits
    root.pendingCmds = []
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

  // Mirrors liked_key() in cliamp_ctl.py: a real target identifies the song, and the
  // title/artist pair stands in for search strings that never resolved to a url.
  function isLiked(url, title, artist) {
    const key = MediaModel.likeKey(url, title, artist)
    return key in root.likedOverrides ? root.likedOverrides[key] : root.likedIndex[key] === true
  }

  function toggleLiked() { root.toggleLikeFor(root.currentUrl, root.currentTrack, root.currentArtist) }

  function toggleLikeFor(url, title, artist) {
    if (!String(url || "").trim() && (!title || title === "No track loaded")) return
    const overrides = Object.assign({}, root.likedOverrides)
    overrides[MediaModel.likeKey(url, title, artist)] = !root.isLiked(url, title, artist)
    root.likedOverrides = overrides
    root._likeDirty = true
    runCmd(["toggle_liked", url || "", title || "", artist || ""])
  }

  function loadPlaylists() {
    if (!playlistsProc.running) playlistsProc.running = true
  }

  function ctlCmd(args) {
    return ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", "")].concat(args)
  }

  function startAction(args) {
    root._commandGen++
    actionProc.command = root.ctlCmd(args)
    actionProc.running = true
  }

  // Actions queue behind each other. Replacing a running one used to drop it, which
  // is what made a second "+" click, or a click paired with another action, vanish.
  function runCmd(args) {
    if (actionProc.running) { root.pendingCmds.push(args); return }
    startAction(args)
  }

  // Sliders emit per-drag-step, where only the newest value matters; these run on
  // their own process so they never cancel a queue write.
  function liveCmd(args) {
    root._commandGen++
    liveProc.running = false
    liveProc.command = root.ctlCmd(args)
    liveProc.running = true
  }

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
        try {
          var data = JSON.parse(text || "{}")
          const fresh = root._statusGen === root._commandGen
          if (fresh && !root.visPickerOpen) {
            if (data.vis_mode && String(data.vis_mode) !== root.visMode) root.visMode = String(data.vis_mode)
            if (data.vis_bg !== undefined) root.visBackground = data.vis_bg === true
            if (data.vis_bg_pulse !== undefined) root.visBackgroundPulse = data.vis_bg_pulse === true
          }
          if (root.syncMpris()) return
          root.isRunning = data.running === true
          if (fresh) root.playbackState = data.state || "stopped"
          var newTrack = String(data.track || "No track loaded")
          var newArtist = String(data.artist || "")
          var newUrl = String(data.url || "")
          var trackChanged = (newTrack !== root.currentTrack) || (newArtist !== root.currentArtist) || (newUrl !== root.currentUrl)
          root.currentTrack = newTrack
          root.currentArtist = newArtist
          root.currentUrl = newUrl
          root.artPath = String(data.art_path || "")
          if (trackChanged && root.open && root.selectedTab === "queue") root.loadQueue()
          if (trackChanged && root.open) root.loadHistory()
          if (trackChanged && playerComp.lyricsVisible && playerComp.lyricsTrackKey !== playerComp.lyricsKey()) {
            playerComp.fetchLyrics()
          }
          root.timeCurrent = String(data.time_current || "00:00")
          root.timeTotal = String(data.time_total || "00:00")
          root.curSecs = Number(data.cur_secs || 0)
          root._lastStatusTime = Date.now()
          if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
          root.totalSecs = Number(data.total_secs || 0)
          root.progress = Number(data.progress || 0.0)
          if (fresh) {
            root.volumePct = (data.volume_pct !== undefined && data.volume_pct !== null) ? Number(data.volume_pct) : 80
            root.playbackSpeed = Number(data.speed || 1.0)
            root.volumeDb = Number(data.volume_db || 0.0)
            root.shuffleMode = data.shuffle === true
            root.repeatMode = String(data.repeat || "off")
          }
          root.eqText = String(data.eq || "Custom")
          if (data.audio_fx) root.audioFx = data.audio_fx
          if (data.resume && root.playbackState === "stopped") {
            root.resumeInfo = data.resume
            // Below the seek threshold in the resume action, so Resume would do
            // nothing the play button does not already do.
            root.resumeVisible = Number(data.resume.pos || 0) > 5
              && String(data.resume.url || "") !== root.resumeDismissedUrl
          } else {
            root.resumeVisible = false
            root.resumeDismissedUrl = ""
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: filesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const data = JSON.parse(text || "{}")
          root.filesPath = data.path || ""
          root.filesParent = data.parent || ""
          root.filesAtRoot = data.atRoot !== false
          root.filesList = data.items || []
        } catch (error) { root.filesList = [] }
      }
    }
  }

  Process {
    id: queueProc
    onExited: function() {
      if (!root.queueReloadPending) return
      root.queueReloadPending = false
      root.startQueueLoad()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const data = JSON.parse(text || "{}")
          root.queueSource = data.source || "cliamp"
          root.queueItems = data.items || []
        } catch (e) { root.queueSource = "cliamp"; root.queueItems = [] }
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
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "history", "99"]
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
        // a reload that raced a still-pending toggle would drop its optimistic flip
        if (!root._likeDirty) root.likedOverrides = ({})
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
            root.loadPlaylists()
          } else {
            root.plImportError = res.error || "Failed to import playlist"
          }
        } catch (e) {
          root.plImportError = "Error importing playlist"
        }
      }
    }
  }

  Process { id: liveProc; onExited: root._commandGen++ }

  Process {
    id: actionProc
    onExited: function() {
      root._commandGen++
      if (root.pendingCmds.length > 0) {
        root.startAction(root.pendingCmds.shift())
        return
      }
      if (root._likeDirty) {
        root._likeDirty = false
        root.loadPlaylists()
      }
      root.loadingVid = ""
      root.refresh()
      if (root.open) root.loadQueue()
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

  // Avoids the first post-reboot play paying mpv's startup cost.
  Process {
    id: warmupProc
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "start_daemon"]
    onExited: root.refresh()
  }

  Process {
    id: spectrumProc
  }

  Timer {
    id: pollTimer
    interval: 500
    running: root.open; repeat: true; triggeredOnStart: true
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

  // a click anywhere else must release the search field, or every single-key
  // shortcut in handleKey stays swallowed by it. DragThreshold keeps the grab
  // passive, so rows and tabs still get their own click.
  TapHandler { gesturePolicy: TapHandler.DragThreshold; onTapped: trackList.urlInput.focus = false }

  header: BorderSurface {
    visible: root.resumeVisible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Commons.Style.space(28)
    radius: root.shell.rounding
    color: root.shell.alpha(root.background, root.surfaceOpacity)
    borderSpec: Commons.Border.flat(root.shell.alpha(Commons.Color.accent, root.borderOpacity), root.shell.borderWidth)

    Item {
      anchors.fill: parent
      anchors.leftMargin: Commons.Style.space(6)
      anchors.rightMargin: Commons.Style.space(6)

      PanelActionButton {
        id: resumeAction
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uf0e2"
        tooltipText: "Resume playback"
        foreground: Commons.Color.accent; hoverColor: Commons.Color.accent
        fontFamily: root.fontFamily
        onClicked: root.doResume()
      }

      Text {
        anchors.left: resumeAction.right
        anchors.leftMargin: Commons.Style.space(2)
        anchors.right: dismissBtn.left
        anchors.rightMargin: Commons.Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: root.resumeInfo ? "Resume at " + Media.time(Number(root.resumeInfo.pos || 0)) : ""
        color: root.foreground
        font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: dismissBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf00d"
        color: dismissMouse.containsMouse ? Commons.Color.accent : root.dim
        font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption

        MouseArea {
          id: dismissMouse
          anchors.fill: parent; anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.resumeDismissedUrl = root.resumeInfo ? String(root.resumeInfo.url || "") : ""
            root.resumeVisible = false
          }
        }
      }
    }
  }

  Column {
        id: mainColumn
        width: parent.width - Commons.Style.space(20)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Commons.Style.space(8)
        topPadding: Commons.Style.space(12)
        bottomPadding: Commons.Style.space(8)

        Player { id: playerComp; controller: root }

        Transport { controller: root }

        PanelSeparator { foreground: root.foreground }

        TrackList { id: trackList; controller: root; visible: !playerComp.lyricsVisible && !root.visPickerOpen && !root.eqPickerOpen }

        Loader {
          visible: root.visPickerOpen
          active: root.visPickerOpen
          width: parent.width
          source: "cliamp/VisPicker.qml"
          onLoaded: { if (item) item.controller = root }
        }

        Loader {
          visible: root.eqPickerOpen
          active: root.eqPickerOpen
          width: parent.width
          source: "cliamp/EqPicker.qml"
          onLoaded: { if (item) item.controller = root }
        }

        Item {
          visible: playerComp.lyricsVisible
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
              height: Math.max(Commons.Style.space(24), lyricsActions.implicitHeight)

              Item {
                anchors.left: parent.left
                anchors.right: lyricsActions.left
                anchors.rightMargin: Commons.Style.space(4)
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Text {
                  id: lyricsGlyph
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf10d"
                  color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
                }
                Text {
                  anchors.left: lyricsGlyph.right
                  anchors.right: parent.right
                  anchors.leftMargin: Commons.Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Lyrics — " + (root.currentTrack || "No track")
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
                  font.bold: true; elide: Text.ElideRight
                }
              }

              Row {
                id: lyricsActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                PanelActionButton { iconText: "\uf021"; tooltipText: "Refresh lyrics"; enabled: !playerComp.lyricsLoading; onClicked: root.lyricsAction("refresh") }
                PanelActionButton { iconText: "−"; tooltipText: "Show lyrics 0.5s earlier"; enabled: playerComp.lyricsTimed && root.shell.store.lyricsDelayTenths > -50; onClicked: root.lyricsAction("earlier") }
                PanelActionButton {
                  iconText: (root.shell.store.lyricsDelayTenths > 0 ? "+" : "") + (root.shell.store.lyricsDelayTenths / 10).toFixed(1) + "s"
                  tooltipText: "Reset lyric timing"
                  implicitWidth: Commons.Style.space(40)
                  enabled: playerComp.lyricsTimed && root.shell.store.lyricsDelayTenths !== 0
                  onClicked: root.lyricsAction("reset")
                }
                PanelActionButton { iconText: "+"; tooltipText: "Show lyrics 0.5s later"; enabled: playerComp.lyricsTimed && root.shell.store.lyricsDelayTenths < 50; onClicked: root.lyricsAction("later") }
                PanelActionButton { iconText: "A−"; tooltipText: "Smaller lyrics"; enabled: root.shell.store.lyricsFontStep > -2; onClicked: root.lyricsAction("smaller") }
                PanelActionButton { iconText: "A+"; tooltipText: "Larger lyrics"; enabled: root.shell.store.lyricsFontStep < 4; onClicked: root.lyricsAction("larger") }
                PanelActionButton {
                  iconText: "\uf05b"; tooltipText: playerComp.lyricsFollowing ? "Following lyrics" : "Resume following"
                  foreground: playerComp.lyricsFollowing ? Commons.Color.accent : root.dim
                  enabled: playerComp.lyricsLines.length > 0
                  onClicked: root.lyricsAction("follow")
                }
                PanelActionButton { iconText: "\uf00d"; tooltipText: "Close lyrics"; onClicked: root.lyricsAction("close") }
              }
            }

            Text {
              visible: playerComp.lyricsLines.length === 0
              anchors.centerIn: parent
              text: playerComp.lyricsLoading ? "Looking up lyrics…" : "No lyrics available"
              color: root.dim; font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption
            }

            ListView {
              id: lyricsList
              readonly property var popup: root
              readonly property var player: playerComp
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
              onMovementStarted: playerComp.lyricsFollowing = false
              WheelHandler {
                blocking: false
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: playerComp.lyricsFollowing = false
              }
              onVisibleChanged: if (visible && playerComp.lyricsFollowing)
                positionViewAtIndex(Math.max(0, playerComp.lyricsCurrentIdx), ListView.Center)

              Connections {
                target: playerComp
                function onLyricsCurrentIdxChanged() {
                  if (playerComp.lyricsFollowing && playerComp.lyricsLines.length)
                    lyricsList.positionViewAtIndex(Math.max(0, playerComp.lyricsCurrentIdx),
                      playerComp.lyricsCurrentIdx < 0 ? ListView.Beginning : ListView.Center)
                }
              }

              delegate: LyricsLine { view: ListView.view }
            }
          }
        }
      }
}

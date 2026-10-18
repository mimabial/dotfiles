pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui
import "cliamp"
import "MediaModel.js" as MediaModel
import "Units.js" as Units

PopupCard {
  id: root
  readonly property int volumeStep: 5
  readonly property int seekStepSeconds: 5
  readonly property int resumeMinSeconds: 5
  popupName: "media"
  keyboardHint: "Tab move · Space play · ↑↓ vol · ←→ seek · / search · Esc"
  padding: 0
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
  readonly property var media: Media

  property bool isRunning: false
  property string playbackState: "stopped"
  readonly property bool isPlaying: playbackState === "playing"
  property string currentTrack: "No track loaded"
  property string currentArtist: ""
  property string currentUrl: ""
  property string artPath: ""
  property color dynamicAccent: Commons.Color.accent
  Behavior on dynamicAccent { ColorAnimation { duration: Style.duration(500); easing.type: Easing.InOutQuad } }
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
  property real lastStatusEpochMs: 0
  property int playbackCommandRevision: 0
  property int statusCommandRevision: 0
  property bool statusPending: false
  property string eqText: "Custom"
  property var audioFx: ({ "eq": "Flat", "loudnorm": false, "spatial": false })
  property int volumeBeforeMute: 80

  property var historyList: []
  readonly property bool historyLocalOnly: root.shell.barLayout.mediaHistoryLocalOnly ?? true
  readonly property var historyGroups: MediaModel.historyGroups(root.historyList, Qt.locale())
  onHistoryLocalOnlyChanged: { root.loadHistory(); root.loadPlaylists() }
  property var playlistsList: []
  property var queueItems: []
  property string queueSource: "cliamp"
  readonly property var queueList: MediaModel.displayQueue(root.queueSource, root.queueItems, {
    state: root.playbackState, title: root.currentTrack, artist: root.currentArtist,
    url: root.currentUrl, art: root.artPath
  })
  property var pendingPlaybackCommands: []
  property bool queueReloadPending: false
  readonly property bool currentLiked: root.isLiked(root.currentUrl, root.currentTrack, root.currentArtist)
  readonly property var likedIndex: {
    const index = ({})
    for (const playlist of root.playlistsList)
      if (playlist.name === "Liked")
        for (const track of playlist.tracks || []) index[MediaModel.likeKey(track.url, track.title, track.artist)] = true
    return index
  }
  property var likedOverrides: ({})
  property bool likeWritePending: false
  property string queueOverride: ""
  property var filesList: []
  property string filesPath: ""
  property string filesParent: ""
  property bool filesAtRoot: true
  property var searchResults: []
  property bool isSearching: false
  property string searchQuery: ""
  property string loadingVid: ""
  property string selectedTab: "recents"
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
    "scatter", "butterfly", "yinyang",
    "plasma", "osc_warp", "crt_scanline", "cyber_tunnel", "red_sector"
  ]

  property var visBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visBandsRaw: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visBandsStereo: ({ "left": [], "right": [] })
  property var visBandsFine: []
  property var visPeaks: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  property var visWave: []
  property var visWaveStereo: ({ "left": [], "right": [] })
  property var visBandsDb: []
  property var visBandEdges: []
  property var visStereo: ({ "levels": [0, 0], "peaks": [0, 0] })
  property var visAnalysis: ({})
  property string pendingSpectrumJson: ""
  property double lastSpectrumCaptureEpochMs: 0
  property double visFrame: 0
  readonly property double visualizerEpochMs: Date.now()
  readonly property double visualizerFrameMilliseconds: 42.7
  readonly property real spectrumRiseSeconds: 0.075
  readonly property real spectrumFallSeconds: 0.23
  property var visualizerState: ({})
  property var resumeInfo: null
  property bool resumeVisible: false
  property string resumeDismissedUrl: ""
  property var selectedPlaylist: null
  readonly property var activePlaylist: {
    const playlist = root.selectedPlaylist
    if (!playlist || playlist.name !== "Recently Played") return playlist
    return { name: playlist.name, system: true, tracks: root.historyList.map(track => ({
      title: track.title || "Track", artist: track.artist || "",
      duration: track.duration_secs ? Units.clockText(track.duration_secs) : "",
      url: track.path || (track.title + " " + track.artist)
    })) }
  }
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
    const player = root.mprisPlayer
    if (!player) return false
    const metadata = player.metadata || ({})
    const newTrack = String(player.trackTitle || "No track loaded")
    const newArtist = Media.displayArtist(player)
    const newUrl = String(metadata["xesam:url"] || "")
    const trackChanged = newTrack !== root.currentTrack || newArtist !== root.currentArtist || newUrl !== root.currentUrl
    root.isRunning = true
    root.playbackState = player.playbackState === MprisPlaybackState.Playing ? "playing"
      : player.playbackState === MprisPlaybackState.Paused ? "paused" : "stopped"
    root.currentTrack = newTrack
    root.currentArtist = newArtist
    root.currentUrl = newUrl
    root.artPath = String(player.trackArtUrl || "")
    root.totalSecs = player.lengthSupported ? Number(player.length || 0) : 0
    root.timeTotal = Units.clockText(root.totalSecs)
    root.playbackSpeed = Number(player.rate || 1)
    if (player.volumeSupported) root.volumePct = Math.round(Number(player.volume || 0) * 100)
    root.shuffleMode = player.shuffleSupported ? player.shuffle : false
    root.repeatMode = !player.loopSupported || player.loopState === MprisLoopState.None ? "off"
      : player.loopState === MprisLoopState.Track ? "track" : "all"
    root.updatePosition(player.positionSupported ? player.position : 0)
    root.resumeVisible = false
    const localPath = newUrl.startsWith("file://") ? decodeURIComponent(newUrl.slice(7)) : ""
    if (trackChanged && localPath && newTrack !== "No track loaded") {
      recentProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""),
        "remember", newTrack, newArtist, localPath]
      recentProcess.running = true
    }
    if (trackChanged && root.open && root.selectedTab === "queue") root.loadQueue()
    if (trackChanged && root.open) root.startSpectrum()
    if (trackChanged && playerComp.lyricsVisible && playerComp.lyricsTrackKey !== playerComp.lyricsKey())
      playerComp.fetchLyrics()
    if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
    return true
  }

  function updatePosition(seconds) {
    const value = Number(seconds)
    if (!Number.isFinite(value)) return
    root.curSecs = Math.max(0, root.totalSecs > 0 ? Math.min(value, root.totalSecs) : value)
    root.progress = root.totalSecs > 0 ? root.curSecs / root.totalSecs : 0
    root.timeCurrent = Units.clockText(root.curSecs)
    root.lastStatusEpochMs = Date.now()
    if (playerComp.lyricsVisible) playerComp.updateLyricsPosition(root.curSecs)
  }

  onMprisPlayerChanged: {
    if (!root.syncMpris()) root.refresh()
    if (root.open) root.startSpectrum()
  }

  onOpenChanged: {
    if (open) {
      if (!root.externalMedia && !root.isRunning) warmupProcess.running = true
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
      trackList.urlInput.focus = false
    }
  }

  Component.onCompleted: {
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
    spectrumProcess.running = false
    spectrumProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "start_spectrum"].concat(spectrumSelectors())
    spectrumProcess.running = true
  }

  function stopSpectrum() {
    spectrumProcess.running = false
    spectrumProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "stop_spectrum"]
    spectrumProcess.running = true
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
    if (event.key === Qt.Key_Up) { root.adjustVolume(root.volumeStep); return true }
    if (event.key === Qt.Key_Down) { root.adjustVolume(-root.volumeStep); return true }
    if (event.key === Qt.Key_Right) { root.seekTo(Math.min(root.totalSecs, root.curSecs + root.seekStepSeconds)); return true }
    if (event.key === Qt.Key_Left) { root.seekTo(Math.max(0, root.curSecs - root.seekStepSeconds)); return true }
    if (event.text === "/") {
      trackList.urlInput.forceActiveFocus()
      trackList.urlInput.selectAll()
      return true
    }
    const row = root.navigableRows[root.cursorIndex]
    if (event.key === Qt.Key_Q && row && row.enqueue) { row.enqueue(); return true }
    if (event.key === Qt.Key_Delete && row && row.dequeue) { row.dequeue(); return true }
    if (event.key === Qt.Key_E) { root.showPane(root.eqPickerOpen ? "" : "eq"); return true }
    if (event.key === Qt.Key_V) { root.showPane(root.visPickerOpen ? "" : "vis"); return true }
    if (event.key === Qt.Key_Y) { playerComp.toggleLyrics(); return true }
    if (event.key === Qt.Key_S) { root.cycleSpeed(); return true }
    if (event.key === Qt.Key_Backspace) {
      if (root.selectedTab === "files" && !root.filesAtRoot) { root.loadFiles(root.filesParent); return true }
      if (root.selectedTab === "playlists" && root.activePlaylist) { root.closePlaylist(); return true }
    }
    if (event.text.toLowerCase() === "m") { root.toggleMute(); return true }
    return root.defaultKey(event)
  }

  function refresh() {
    if (statusProcess.running) { root.statusPending = true; return }
    if (actionProcess.running) return
    root.statusCommandRevision = root.playbackCommandRevision
    statusProcess.running = true
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
    enqueuePlaybackCommand(["set_eq", preset])
  }
  function setVisMode(mode) {
    if (!mode) return
    root.visMode = mode
    enqueuePlaybackCommand(["set_vis_mode", mode])
    if (playerComp) playerComp.requestPaint()
  }
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
      lyricsList.positionViewAtIndex(Math.max(0, playerComp.currentLyricsIndex),
        playerComp.currentLyricsIndex < 0 ? ListView.Beginning : ListView.Center)
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
    enqueuePlaybackCommand(["set_vis_bg", enabled ? "1" : "0"])
    if (playerComp) playerComp.requestPaint()
  }
  function setVisBackgroundPulse(enabled) {
    root.visBackgroundPulse = enabled
    enqueuePlaybackCommand(["set_vis_bg_pulse", enabled ? "1" : "0"])
    if (playerComp) playerComp.requestPaint()
  }
  function toggleLoudnorm() {
    enqueuePlaybackCommand(["toggle_loudnorm"])
    var next = !(root.audioFx && root.audioFx.loudnorm)
    root.audioFx = { eq: root.eqText, loudnorm: next, spatial: root.audioFx ? root.audioFx.spatial : false }
  }
  function toggleSpatial() {
    enqueuePlaybackCommand(["toggle_spatial"])
    var next = !(root.audioFx && root.audioFx.spatial)
    root.audioFx = { eq: root.eqText, loudnorm: root.audioFx ? root.audioFx.loudnorm : false, spatial: next }
  }
  function importPlaylist(url, name) {
    if (!url || !url.trim() || root.isImportingPl) return
    root.isImportingPl = true
    root.plImportError = ""
    root.selectedTab = "playlists"
    root.selectedPlaylist = null
    importPlProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "import_playlist", url.trim(), name || ""]
    importPlProcess.running = true
  }

  function deletePlaylist(name) {
    if (!name) return
    if (root.activePlaylist && root.activePlaylist.name === name) {
      root.selectedPlaylist = null
    }
    enqueuePlaybackCommand(["delete_playlist", name])
    Qt.callLater(loadPlaylists)
  }

  function openPlaylist(playlist) {
    if (playlist) root.selectedPlaylist = playlist
  }

  function closePlaylist() {
    root.selectedPlaylist = null
  }

  function doResume() { enqueuePlaybackCommand(["resume"]); root.resumeVisible = false; root.loadingVid = "" }

  function playUrl(url, title, artist, keepQueue) {
    if (!url || !url.trim()) return
    const active = root.mprisPlayer
    if (active && active.isPlaying && active.canPause) active.pause()
    var target = url.trim()
    root.loadingVid = target
    root.currentTrack = title || "Buffering..."
    root.currentArtist = artist || ""
    root.playbackState = "buffering"
    enqueuePlaybackCommand([keepQueue ? "play_item" : "play_replace", target, title || "", artist || ""])
    root.urlInputText = ""
  }

  function playOrToggle(current, url, title, artist) {
    if (current && root.playbackState !== "stopped") root.togglePlayback()
    else if (url) root.playUrl(url, title, artist)
  }

  function queueUrl(url, title, artist) {
    if (!url || !url.trim()) return
    root.queueOverride = "cliamp"
    enqueuePlaybackCommand(["queue", url.trim(), title || "", artist || ""])
    root.urlInputText = ""
  }

  function queueDir(rel) {
    root.queueOverride = "cliamp"
    enqueuePlaybackCommand(["queue_dir", rel || ""])
  }

  function playDir(rel) {
    root.queueOverride = "cliamp"
    root.pendingPlaybackCommands = []
    root.playbackState = "buffering"
    enqueuePlaybackCommand(["play_dir", rel || ""])
  }

  function queueContext() {
    return MediaModel.queueContext(root.queueOverride, root.mprisPlayer)
  }

  function loadFiles(rel) {
    if (filesProcess.running) return
    filesProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "files", rel || ""]
    filesProcess.running = true
  }

  function startQueueLoad() {
    queueProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "queue_list", queueContext()]
    queueProcess.running = true
  }

  function loadQueue() {
    if (queueProcess.running) { root.queueReloadPending = true; return }
    startQueueLoad()
  }

  function playQueueItem(item) {
    if (item.current === true) { togglePlayback(); return }
    if (item.backend === "mpd") { enqueuePlaybackCommand(["mpd_play", String(item.position)]); return }
    if (item.backend === "youtube" && root.mprisPlayer) {
      root.mprisPlayer.openUri(item.url); Media.select(root.mprisPlayer); return
    }
    if (!item.url || !item.url.trim()) return
    playUrl(item.url, item.title, item.artist, true)
    removeFromQueue(item.queueIndex)
  }

  function clearQueue() {
    root.pendingPlaybackCommands = []
    enqueuePlaybackCommand(["queue_clear"])
  }

  function removeFromQueue(idx) {
    enqueuePlaybackCommand(["queue_remove", String(idx)])
  }

  function searchTracks(query) {
    if (!query || !query.trim()) return
    var term = query.trim()
    if (term.indexOf("http://") === 0 || term.indexOf("https://") === 0) {
      if (term.indexOf("list=") !== -1 || term.indexOf("/playlist/") !== -1 || term.indexOf("/album/") !== -1) {
        importPlaylist(term)
        root.selectedTab = "playlists"
        return
      }
      playUrl(term)
      return
    }
    root.isSearching = true
    root.searchQuery = term
    root.selectedTab = "search"
    searchProcess.command = ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "search", term]
    searchProcess.running = true
  }

  function clearSearch() {
    root.searchQuery = ""
    root.searchResults = []
    root.isSearching = false
    root.selectedTab = "recents"
  }

  function playPlaylist(playlist) {
    if (!playlist || !playlist.tracks || playlist.tracks.length === 0) return
    var first = playlist.tracks[0]
    playUrl(first.url || (first.title + " " + first.artist), first.title, first.artist)
    for (var i = 1; i < playlist.tracks.length; i++) {
      var track = playlist.tracks[i]
      queueUrl(track.url || (track.title + " " + track.artist), track.title, track.artist)
    }
  }

  function stopDaemon() {
    enqueuePlaybackCommand(["stop_daemon"])
    root.isRunning = false
    root.playbackState = "stopped"
  }

  function loadHistory() {
    if (historyProcess.running) return
    historyProcess.localOnly = root.historyLocalOnly
    historyProcess.running = true
  }

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
    root.likeWritePending = true
    enqueuePlaybackCommand(["toggle_liked", url || "", title || "", artist || ""])
  }

  function loadPlaylists() {
    if (playlistsProcess.running) return
    playlistsProcess.localOnly = root.historyLocalOnly
    playlistsProcess.running = true
  }

  function playbackHelperCommand(args) {
    return ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", "")].concat(args)
  }

  function startAction(args) {
    root.playbackCommandRevision++
    actionProcess.command = root.playbackHelperCommand(args)
    actionProcess.running = true
  }

  function enqueuePlaybackCommand(args) {
    if (actionProcess.running) { root.pendingPlaybackCommands.push(args); return }
    startAction(args)
  }

  function replaceLivePlaybackCommand(args) {
    root.playbackCommandRevision++
    liveProcess.running = false
    liveProcess.command = root.playbackHelperCommand(args)
    liveProcess.running = true
  }

  Connections {
    target: root.mprisPlayer
    function onMetadataChanged() { root.syncMpris() }
    function onPlaybackStateChanged() { root.syncMpris() }
    function onPositionChanged() { root.updatePosition(root.mprisPlayer.position) }
    function onLengthChanged() { root.syncMpris() }
    function onVolumeChanged() { root.syncMpris() }
    function onRateChanged() { root.syncMpris() }
  }

  Connections {
    target: Media
    function onElapsedChanged() { if (root.open && root.mprisPlayer) root.updatePosition(Media.elapsed) }
  }

  Process {
    id: statusProcess
    onRunningChanged: if (!running && root.statusPending) { root.statusPending = false; root.refresh() }
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          const fresh = root.statusCommandRevision === root.playbackCommandRevision
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
          root.lastStatusEpochMs = Date.now()
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
            root.resumeVisible = Number(data.resume.pos || 0) > root.resumeMinSeconds
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
    id: filesProcess
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
    id: queueProcess
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
  Connections {
    target: queueProcess
    function onExited() {
      if (!root.queueReloadPending) return
      root.queueReloadPending = false
      root.startQueueLoad()
    }
  }

  Process {
    id: searchProcess
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
    id: historyProcess
    property bool localOnly: true
    command: root.playbackHelperCommand(["history", "99"].concat(historyProcess.localOnly ? ["--local-only"] : []))
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (historyProcess.localOnly !== root.historyLocalOnly) return
        try { root.historyList = JSON.parse(text || "[]") }
        catch (e) { root.historyList = [] }
      }
    }
  }
  Connections { target: historyProcess; function onExited() { if (historyProcess.localOnly !== root.historyLocalOnly) root.loadHistory() } }

  Process { id: recentProcess }
  Connections { target: recentProcess; function onExited() { if (root.open) root.loadHistory() } }

  Process {
    id: playlistsProcess
    property bool localOnly: true
    command: root.playbackHelperCommand(["playlists"].concat(playlistsProcess.localOnly ? ["--local-only"] : []))
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (playlistsProcess.localOnly !== root.historyLocalOnly) return
        try { root.playlistsList = JSON.parse(text || "[]") }
        catch (e) { root.playlistsList = [] }
        if (!root.likeWritePending) root.likedOverrides = ({})
      }
    }
  }
  Connections { target: playlistsProcess; function onExited() { if (playlistsProcess.localOnly !== root.historyLocalOnly) root.loadPlaylists() } }

  Process {
    id: importPlProcess
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

  Process { id: liveProcess }
  Connections { target: liveProcess; function onExited() { root.playbackCommandRevision++ } }

  Process { id: actionProcess }
  Connections {
    target: actionProcess
    function onExited() {
      root.playbackCommandRevision++
      if (root.pendingPlaybackCommands.length > 0) {
        root.startAction(root.pendingPlaybackCommands.shift())
        return
      }
      if (root.likeWritePending) {
        root.likeWritePending = false
        root.loadPlaylists()
      }
      root.loadingVid = ""
      root.refresh()
      if (root.open) root.loadQueue()
    }
  }

  Process {
    id: warmupProcess
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "start_daemon"]
  }
  Connections { target: warmupProcess; function onExited() { root.refresh() } }

  Process {
    id: spectrumProcess
  }

  Process {
    command: ["python3", Qt.resolvedUrl("cliamp/cliamp_ctl.py").toString().replace("file://", ""), "watch"]
    running: root.open && !root.externalMedia && root.isRunning
    onRunningChanged: if (!running && root.open && !root.externalMedia) root.refresh()
    stdout: SplitParser { onRead: line => {
        const event = JSON.parse(line)
        if (event.name === "time-pos") root.updatePosition(event.data)
        else root.refresh()
    } }
  }
  Instantiator {
    model: ["vis_mode.txt", "vis_bg.txt", "vis_bg_pulse.txt", "audio_fx.json", "eq.json"]
    delegate: FileView {
      required property string modelData
      path: root.shell.home + "/.cache/cliamp/" + modelData; watchChanges: root.open; printErrors: false
      onFileChanged: { reload(); root.refresh() }
    }
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
    onLoaded: root.pendingSpectrumJson = text()
    onLoadFailed: {}
  }

  function unitLevel(value) {
    return Math.min(1.0, Math.max(0.0, Number(value) || 0.0))
  }

  function easeLevel(previous, target, dt) {
    var tau = target > previous ? root.spectrumRiseSeconds : root.spectrumFallSeconds
    var eased = previous + (target - previous) * (1.0 - Math.exp(-dt / tau))
    return target === 0 && eased < 0.001 ? 0 : eased
  }

  function decayLevels(levels) {
    return levels.map(level => Math.max(0, level * 0.8 - 0.02))
  }

  function updateSpectrumData(raw) {
    if (!root.open) return
    if (!root.isPlaying) {
      root.visBands = decayLevels(root.visBands); root.visPeaks = decayLevels(root.visPeaks); root.visBandsFine = decayLevels(root.visBandsFine)
      if (playerComp && root.visBands.concat(root.visPeaks, root.visBandsFine).some(level => level > 0)) playerComp.requestPaint()
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
        if (capturedAt === root.lastSpectrumCaptureEpochMs) return
        var spectrumDt = root.lastSpectrumCaptureEpochMs > 0 ? Math.min(0.12, Math.max(0.015, (capturedAt - root.lastSpectrumCaptureEpochMs) / 1000.0)) : root.visualizerFrameMilliseconds / 1000.0
        root.lastSpectrumCaptureEpochMs = capturedAt
        var stereoBands = data.bands_stereo || ({}), stereoLeft = stereoBands.left || [], stereoRight = stereoBands.right || []
        var previousStereo = root.visBandsStereo || ({}), previousLeft = previousStereo.left || [], previousRight = previousStereo.right || []
        var newBands = [], newRawBands = [], newPeaks = [], newLeft = [], newRight = []
        for (var i = 0; i < 24; i++) {
          var target = root.unitLevel(bands[i])
          var display = root.easeLevel(Number(root.visBands[i]) || 0.0, target, spectrumDt)
          var prevPeak = root.visPeaks[i] || 0.0
          newRawBands.push(target)
          newBands.push(display)
          newPeaks.push(Math.max(display, prevPeak - 0.38 * spectrumDt))
          newLeft.push(root.easeLevel(Number(previousLeft[i]) || 0.0, root.unitLevel(stereoLeft[i]), spectrumDt))
          newRight.push(root.easeLevel(Number(previousRight[i]) || 0.0, root.unitLevel(stereoRight[i]), spectrumDt))
        }
        root.visBandsRaw = newRawBands; root.visBands = newBands; root.visPeaks = newPeaks
        root.visBandsFine = (data.bands_fine || []).map((level, index) =>
          root.easeLevel(Number(root.visBandsFine[index]) || 0.0, root.unitLevel(level), spectrumDt))
        root.visBandsStereo = ({ "left": newLeft, "right": newRight })
        root.visWave = Array.isArray(data.wave) ? data.wave : []
        root.visWaveStereo = data.wave_stereo || ({ "left": [], "right": [] })
        root.visBandsDb = Array.isArray(data.bands_dbfs) ? data.bands_dbfs : []
        root.visBandEdges = Array.isArray(data.band_edges_hz) ? data.band_edges_hz : []
        root.visStereo = data.stereo || ({ "levels": [0, 0], "peaks": [0, 0] })
        root.visAnalysis = analysis
        root.visFrame = Math.floor((Date.now() - root.visualizerEpochMs) / root.visualizerFrameMilliseconds)
        if (playerComp) playerComp.requestPaint()
      }
    } catch (e) {}
  }

  Timer {
    id: visTimer
    interval: Math.round(root.visualizerFrameMilliseconds); running: root.open; repeat: true
    onTriggered: {
      if (root.isPlaying) {
        root.updateSpectrumData(root.pendingSpectrumJson)
        specFile.reload()
        if (playerComp && playerComp.lyricsVisible && root.lastStatusEpochMs > 0) {
          var elapsed = (Date.now() - root.lastStatusEpochMs) / 1000.0
          playerComp.updateLyricsPosition(root.curSecs + elapsed * root.playbackSpeed)
        }
      } else {
        root.updateSpectrumData("")
      }
    }
  }

  TapHandler { gesturePolicy: TapHandler.DragThreshold; onTapped: trackList.urlInput.focus = false }

  header: BorderSurface {
    visible: root.resumeVisible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Commons.Style.space(28)
    radius: root.shell.rounding
    color: root.shell.alpha(Commons.Style.popupTinted(root.background), root.surfaceOpacity)
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
        text: root.resumeInfo ? "Resume at " + Units.clockText(Number(root.resumeInfo.pos || 0)) : ""
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
                positionViewAtIndex(Math.max(0, playerComp.currentLyricsIndex), ListView.Center)

              Connections {
                target: playerComp
                function onCurrentLyricsIndexChanged() {
                  if (playerComp.lyricsFollowing && playerComp.lyricsLines.length)
                    lyricsList.positionViewAtIndex(Math.max(0, playerComp.currentLyricsIndex),
                      playerComp.currentLyricsIndex < 0 ? ListView.Beginning : ListView.Center)
                }
              }

              delegate: LyricsLine { view: ListView.view }
            }
          }
        }
      }
}

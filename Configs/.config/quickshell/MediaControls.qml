import QtQuick
import Quickshell.Services.Mpris

QtObject {
  id: controls
  readonly property int defaultVolume: 80
  required property var controller
  required property var media

  function togglePlayback() {
    const player = controls.controller.mprisPlayer
    if (player) {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
      controls.media.select(player)
      controls.controller.syncMpris()
      return
    }
    controls.controller.playbackState = (controls.controller.playbackState === "playing") ? "paused" : "playing"
    controls.controller.runCmd(["toggle"])
  }
  function play() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.canPlay) player.play(); controls.media.select(player); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "playing"
    controls.controller.runCmd(["play"])
  }
  function pause() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.canPause) player.pause(); controls.media.select(player); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "paused"
    controls.controller.runCmd(["pause"])
  }
  function stop() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.canControl) player.stop(); controls.media.select(player); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "stopped"
    controls.controller.runCmd(["stop"])
  }
  function nextTrack() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.canGoNext) player.next(); controls.media.select(player); return }
    controls.controller.runCmd(["next"])
  }
  function prevTrack() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.canGoPrevious) player.previous(); controls.media.select(player); return }
    controls.controller.runCmd(["prev"])
  }
  function toggleShuffle() {
    const player = controls.controller.mprisPlayer
    if (player) { if (player.shuffleSupported) player.shuffle = !player.shuffle; return }
    controls.controller.runCmd(["shuffle"])
  }
  function cycleRepeat() {
    const player = controls.controller.mprisPlayer
    if (player) {
      if (player.loopSupported) player.loopState = player.loopState === MprisLoopState.None
        ? MprisLoopState.Track : player.loopState === MprisLoopState.Track
          ? MprisLoopState.Playlist : MprisLoopState.None
      return
    }
    controls.controller.runCmd(["repeat"])
  }
  
  function adjustVolume(delta) {
    setVolume(Math.max(0, Math.min(100, controls.controller.volumePct + delta)))
  }
  
  function setVolume(pct) {
    controls.controller.volumePct = pct
    const player = controls.controller.mprisPlayer
    if (player) { if (player.volumeSupported) player.volume = pct / 100; return }
    controls.controller.liveCmd(["volume_pct", String(pct)])
  }
  
  function toggleMute() {
    if (controls.controller.volumePct > 0) {
      controls.controller._preMuteVol = controls.controller.volumePct
      setVolume(0)
    } else {
      var target = (controls.controller._preMuteVol && controls.controller._preMuteVol > 0) ? controls.controller._preMuteVol : controls.defaultVolume
      setVolume(target)
    }
  }
  
  function seekTo(sec) {
    const player = controls.controller.mprisPlayer
    if (player) {
      if (player.canSeek && player.positionSupported) {
        player.position = sec
        controls.controller.updatePosition(sec)
      }
      return
    }
    controls.controller.liveCmd(["seek", String(sec)])
  }
  function cycleSpeed() {
    var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var cur = controls.controller.playbackSpeed
    var idx = 0
    for (var i = 0; i < speeds.length; i++) { if (Math.abs(speeds[i] - cur) < 0.05) { idx = i; break } }
    var next = speeds[(idx + 1) % speeds.length]
    controls.controller.playbackSpeed = next
    const player = controls.controller.mprisPlayer
    if (player) { player.rate = Math.max(player.minRate, Math.min(player.maxRate, next)); return }
    controls.controller.runCmd(["speed", String(next)])
  }
}

import QtQuick
import Quickshell.Services.Mpris

QtObject {
  id: controls
  required property var controller
  required property var media

  function togglePlayback() {
    const p = controls.controller.mprisPlayer
    if (p) {
      if (p.isPlaying && p.canPause) p.pause()
      else if (!p.isPlaying && p.canPlay) p.play()
      else if (p.canTogglePlaying) p.togglePlaying()
      controls.media.select(p)
      controls.controller.syncMpris()
      return
    }
    controls.controller.playbackState = (controls.controller.playbackState === "playing") ? "paused" : "playing"
    controls.controller.runCmd(["toggle"])
  }
  function play() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.canPlay) p.play(); controls.media.select(p); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "playing"
    controls.controller.runCmd(["play"])
  }
  function pause() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.canPause) p.pause(); controls.media.select(p); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "paused"
    controls.controller.runCmd(["pause"])
  }
  function stop() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.canControl) p.stop(); controls.media.select(p); controls.controller.syncMpris(); return }
    controls.controller.playbackState = "stopped"
    controls.controller.runCmd(["stop"])
  }
  function nextTrack() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.canGoNext) p.next(); controls.media.select(p); return }
    controls.controller.runCmd(["next"])
  }
  function prevTrack() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.canGoPrevious) p.previous(); controls.media.select(p); return }
    controls.controller.runCmd(["prev"])
  }
  function toggleShuffle() {
    const p = controls.controller.mprisPlayer
    if (p) { if (p.shuffleSupported) p.shuffle = !p.shuffle; return }
    controls.controller.runCmd(["shuffle"])
  }
  function cycleRepeat() {
    const p = controls.controller.mprisPlayer
    if (p) {
      if (p.loopSupported) p.loopState = p.loopState === MprisLoopState.None
        ? MprisLoopState.Track : p.loopState === MprisLoopState.Track
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
    const p = controls.controller.mprisPlayer
    if (p) { if (p.volumeSupported) p.volume = pct / 100; return }
    controls.controller.liveCmd(["volume_pct", String(pct)])
  }
  
  function toggleMute() {
    if (controls.controller.volumePct > 0) {
      controls.controller._preMuteVol = controls.controller.volumePct
      setVolume(0)
    } else {
      var target = (controls.controller._preMuteVol && controls.controller._preMuteVol > 0) ? controls.controller._preMuteVol : 80
      setVolume(target)
    }
  }
  
  function seekTo(sec) {
    const p = controls.controller.mprisPlayer
    if (p) {
      if (p.canSeek && p.positionSupported) {
        p.position = sec
        controls.controller.applyMprisPosition(sec)
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
    const p = controls.controller.mprisPlayer
    if (p) { p.rate = Math.max(p.minRate, Math.min(p.maxRate, next)); return }
    controls.controller.runCmd(["speed", String(next)])
  }
}

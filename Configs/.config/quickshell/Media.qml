pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root
    property int tick: 0
    property string selectedPlayer: ""
    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var sourcePlayers: availablePlayers()
    readonly property var player: chooseActivePlayer()
    readonly property bool hasMedia: player !== null
        && player.playbackState !== MprisPlaybackState.Stopped && hasTrack(player)
    readonly property string title: player ? String(player.trackTitle || "") : ""
    readonly property string artist: displayArtist(player)
    readonly property string album: player ? String(player.trackAlbum || "") : ""
    readonly property string artUrl: player ? String(player.trackArtUrl || "") : ""

    readonly property real elapsed: { tick; return player && player.positionSupported ? player.position : 0 }

    function playerKey(player) {
        return player ? String(player.dbusName || player.desktopEntry || player.identity || player.uniqueId || "").replace(/^org\.mpris\.MediaPlayer2\./, "") : ""
    }
    function displayArtist(player) {
        if (!player) return ""
        const artist = String(player.trackArtist || "").trim()
        if (!artist) return ""
        const metadata = player.metadata || ({})
        const mediaUrl = String(metadata["xesam:url"] || "")
        const hostMatch = mediaUrl.match(/^[a-z][a-z0-9+.-]*:\/\/([^/:?#]+)/i)
        if (!hostMatch) return artist
        const host = hostMatch[1].toLowerCase().replace(/^www\./, "")
        const artistHost = artist.toLowerCase()
            .replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
            .split(/[\/?#]/, 1)[0]
            .replace(/^www\./, "")
        return artistHost === host ? "" : artist
    }
    function isProxy(player) {
        if (!player) return false
        const dbus = String(player.dbusName || "").toLowerCase()
        const desktop = String(player.desktopEntry || "").toLowerCase()
        return dbus.includes("playerctld") || desktop === "playerctld"
    }
    function hasTrack(player) { return !!(player && (player.trackTitle || player.trackArtist || player.trackArtUrl)) }
    function isAvailable(player) {
        return !!(player && player.playbackState !== MprisPlaybackState.Stopped && hasTrack(player))
    }
    function availablePlayers() { return players.filter(player => isAvailable(player)) }
    function preferredPlayer() {
        for (let i = 0; i < sourcePlayers.length; ++i)
            if (playerKey(sourcePlayers[i]) === selectedPlayer) return sourcePlayers[i]
        return null
    }
    function firstMatching(playing, proxy) {
        for (let i = 0; i < sourcePlayers.length; ++i) {
            const candidate = sourcePlayers[i]
            if (!!candidate.isPlaying === playing && isProxy(candidate) === proxy) return candidate
        }
        return null
    }
    function chooseActivePlayer() {
        const preferred = preferredPlayer()
        if (preferred && preferred.isPlaying) return preferred
        return firstMatching(true, false) || firstMatching(true, true) || preferred
            || firstMatching(false, false) || firstMatching(false, true) || null
    }

    function time(seconds) {
        const total = Math.max(0, Math.floor(seconds)), h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60
        const pad = value => String(value).padStart(2, "0")
        return h ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
    }
    function select(player) {
        const key = playerKey(player)
        if (key && key !== selectedPlayer) { selectedPlayer = key; selection.setText(JSON.stringify({ player: key, updated_at: Date.now() / 1000 }) + "\n") }
    }
    function playPause() {
        const target = player
        if (!target) return false
        if (target.isPlaying && target.canPause) target.pause()
        else if (!target.isPlaying && target.canPlay) target.play()
        else if (target.canTogglePlaying) target.togglePlaying()
        else return false
        select(target)
        return true
    }
    function previous() {
        if (!player || !player.canGoPrevious) return false
        player.previous()
        select(player)
        return true
    }
    function next() {
        if (!player || !player.canGoNext) return false
        player.next()
        select(player)
        return true
    }
    function raisePlayer() {
        if (!player || !player.canRaise) return false
        player.raise()
        select(player)
        return true
    }
    // all three from Material Design so the states share an optical box
    function icon(player) {
        if (!player) return "󰓛"
        return player.playbackState === MprisPlaybackState.Playing ? "󰼛"
            : player.playbackState === MprisPlaybackState.Paused ? "󰏤"
            : "󰓛"
    }
    function remaining(player) {
        tick
        if (!player || !player.lengthSupported || !player.positionSupported) return "LIVE"
        const total = Math.max(0, Math.ceil(player.length - player.position)), h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60
        const pad = value => String(value).padStart(2, "0")
        return h ? pad(h) + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }

    function statusObject() {
        return {
            available: hasMedia,
            playing: !!(player && player.isPlaying),
            player: player ? String(player.identity || player.desktopEntry || player.dbusName || "") : "",
            artist, title, album, artUrl,
            canGoPrevious: !!(player && player.canGoPrevious),
            canGoNext: !!(player && player.canGoNext)
        }
    }

    FileView {
        id: selection
        path: Quickshell.env("HOME") + "/.local/state/hypr/mediaplayer.json"; watchChanges: true; printErrors: false; atomicWrites: true
        onLoaded: { try { root.selectedPlayer = String(JSON.parse(selection.text()).player || "") } catch (error) { root.selectedPlayer = "" } }
        onFileChanged: selection.reload()
    }
    Timer { interval: 1000; repeat: true; running: root.player && root.player.isPlaying; onTriggered: ++root.tick }

}

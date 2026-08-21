pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root
    property int tick: 0
    readonly property var player: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; ++i) if (players[i].dbusName === store.lastPlayer) return players[i]
        for (let i = 0; i < players.length; ++i) if (players[i].isPlaying) return players[i]
        return players.length ? players[0] : null
    }

    readonly property real elapsed: { tick; return player && player.positionSupported ? player.position : 0 }

    function time(seconds) {
        const total = Math.max(0, Math.floor(seconds)), h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60
        const pad = value => String(value).padStart(2, "0")
        return h ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
    }
    function select(player) { if (player) store.lastPlayer = player.dbusName }
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

    PersistentProperties { id: store; property string lastPlayer: "" }
    Timer { interval: 1000; repeat: true; running: root.player && root.player.isPlaying; onTriggered: ++root.tick }
    Instantiator {
        model: Mpris.players
        delegate: QtObject {
            required property var modelData
            property bool playing: modelData.isPlaying
            onPlayingChanged: if (playing) root.select(modelData)
            Component.onCompleted: if (playing) root.select(modelData)
        }
    }
}

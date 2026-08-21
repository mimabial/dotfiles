import QtQuick
import Quickshell.Services.Mpris

PopupCard {
    id: root
    popupName: "media"
    contentWidth: 360
    contentHeight: mediaColumn.implicitHeight + 32
    readonly property var player: Media.player
    readonly property var players: player ? [player].concat(Mpris.players.values.filter(item => item !== player)) : Mpris.players.values
    readonly property var controls: {
        const p = root.player
        const loop = ["󰑗", "󰑖", "󰑘"]
        return [
            { glyph: p && p.shuffle ? "󰒟" : "󰒞", size: 18, enabled: !!(p && p.shuffleSupported), lit: !!(p && p.shuffle) },
            { glyph: "󰒮", size: 18, enabled: !!(p && p.canGoPrevious), lit: false },
            { glyph: p && p.isPlaying ? "󰏤" : "󰐊", size: 22, enabled: !!p, lit: false },
            { glyph: "󰒭", size: 18, enabled: !!(p && p.canGoNext), lit: false },
            { glyph: loop[p ? p.loopState : 0], size: 18, enabled: !!(p && p.loopSupported), lit: !!(p && p.loopState !== MprisLoopState.None) }
        ]
    }
    function activate(index) {
        const p = root.player
        if (!p) return
        if (index === 0) p.shuffle = !p.shuffle
        else if (index === 1) p.previous()
        else if (index === 2) p.togglePlaying()
        else if (index === 3) p.next()
        else p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Track
            : p.loopState === MprisLoopState.Track ? MprisLoopState.Playlist : MprisLoopState.None
    }

    Column {
        id: mediaColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: 14
        PopupSection { shell: root.shell; text: "NOW PLAYING" }
        Row {
            width: parent.width; spacing: 12
            Rectangle {
                width: 84; height: 84; radius: root.shell.rounding; clip: true; color: root.shell.alpha(root.shell.foreground, .08)
                Image { anchors.fill: parent; source: root.player ? root.player.trackArtUrl : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                Text { anchors.centerIn: parent; visible: !root.player || !root.player.trackArtUrl; text: "󰝚"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 32 }
            }
            Column {
                width: parent.width - 96; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Text { width: parent.width; text: root.player ? root.player.trackTitle || "Nothing playing" : "Nothing playing"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                Text { visible: text !== ""; width: parent.width; text: root.player ? root.player.trackArtist : ""; color: root.shell.alpha(root.shell.foreground, .7); font.family: root.shell.fontFamily; font.pixelSize: 12; elide: Text.ElideRight }
                Text { visible: text !== ""; width: parent.width; text: root.player ? root.player.trackAlbum : ""; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: 10; elide: Text.ElideRight }
            }
        }
        PopupSlider {
            id: seekBar
            readonly property real duration: root.player && root.player.lengthSupported ? root.player.length : 0
            visible: root.player && root.player.lengthSupported && root.player.positionSupported
            enabled: root.player && root.player.canSeek
            opacity: enabled ? 1 : .45
            width: parent.width; shell: root.shell
            label: Media.time(Media.elapsed)
            valueText: Media.time(duration)
            value: duration > 0 ? Media.elapsed / duration : 0
            onReleased: value => { if (root.player && root.player.canSeek) root.player.position = value * duration }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
            Repeater {
                model: root.controls
                Rectangle {
                    required property int index; required property var modelData
                    width: 44; height: 40; radius: root.shell.rounding
                    color: controlMouse.containsMouse ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), Style.hoverFillAlpha) : "transparent"
                    opacity: modelData.enabled ? 1 : .35
                    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                    Text {
                        anchors.centerIn: parent; text: parent.modelData.glyph
                        color: parent.modelData.lit ? root.shell.accent : root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: parent.modelData.size
                    }
                    MouseArea { id: controlMouse; anchors.fill: parent; enabled: parent.modelData.enabled; hoverEnabled: true; onClicked: root.activate(parent.index) }
                }
            }
        }
        PopupSeparator { visible: root.players.length > 1; shell: root.shell }
        PopupSection { visible: root.players.length > 1; shell: root.shell; text: "PLAYERS" }
        Repeater {
            model: root.players
            PopupRow {
                required property var modelData
                visible: root.players.length > 1; width: parent.width; shell: root.shell; icon: Media.icon(modelData)
                title: modelData.trackTitle || modelData.identity || "Media player"; detail: modelData.trackArtist || modelData.identity; active: modelData === root.player
                onClicked: Media.select(modelData)
            }
        }
    }
}

import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool live: source && !source.audio.muted
    css: live ? "custom-microphone" : "custom-microphone.muted"
    radius: shell.moduleRadius
    outline: shell.alpha(shell.role(live ? "c1" : "br", shell.foreground), .3)
    text: !root.source || root.source.audio.muted ? "󰍭" : "󰍬"
    tooltip: source ? "Microphone " + Math.round(source.audio.volume * 100) + "%" : "No microphone"
    onClicked: if (source) source.audio.muted = !source.audio.muted

    PwObjectTracker { objects: [root.source].filter(x => x) }
}

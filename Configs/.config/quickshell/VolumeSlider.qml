import QtQuick
import Quickshell.Services.Pipewire

BarSlider {
    id: root
    property bool microphone: false
    readonly property var node: microphone ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    css: microphone ? "microphone-slider" : "volume-slider"
    to: microphone ? 1 : shell.volumeLimit
    value: node?.audio?.volume ?? 0
    onMoved: value => { if (root.node?.audio) root.node.audio.volume = value }
    PwObjectTracker { objects: [root.node].filter(x => x) }
}

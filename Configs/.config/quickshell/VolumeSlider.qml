import QtQuick
import Quickshell.Services.Pipewire

BarSlider {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    css: "pulseaudio-slider"
    to: shell.volumeLimit
    value: sink ? sink.audio.volume : 0
    onMoved: value => { if (sink) sink.audio.volume = value }
    PwObjectTracker { objects: [root.sink].filter(x => x) }
}

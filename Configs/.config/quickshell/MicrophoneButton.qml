import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool live: source && !source.audio.muted
    css: live ? "microphone" : "microphone.muted"
    radius: shell.moduleRadius
    text: !root.source || root.source.audio.muted ? "" : ""
    tooltip: !root.source ? "No input device"
        : "Input level: " + Math.round(root.source.audio.volume * 100) + "%"
            + (root.source.audio.muted ? " (muted)" : "")
            + "\nUsing: " + (root.source.description || root.source.nickname || root.source.name)
    onClicked: button => button === Qt.RightButton
        ? (source ? source.audio.muted = !source.audio.muted : false)
        : shell.togglePopup("audio")

    PwObjectTracker { objects: [root.source].filter(x => x) }
}

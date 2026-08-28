import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool live: source && !source.audio.muted
    css: live ? "microphone" : "microphone.muted"
    radius: shell.moduleRadius
    text: !root.source || root.source.audio.muted ? "" : ""
    onClicked: button => button === Qt.RightButton
        ? (source ? source.audio.muted = !source.audio.muted : false)
        : shell.togglePopup("audio")

    PwObjectTracker { objects: [root.source].filter(x => x) }
}

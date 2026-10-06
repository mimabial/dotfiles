import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var source: Pipewire.defaultAudioSource
    readonly property int recordingCount: Pipewire.nodes.values.filter(node => node && node.isStream && node.isSink && node.audio
        && Pipewire.linkGroups.values.some(group => group.target === node && group.source && !group.source.isSink
            && !group.source.isStream && !String(group.source.name).endsWith(".monitor"))).length
    readonly property bool live: source && !source.audio.muted
    css: live ? "microphone" : "microphone.muted"
    text: !root.source || root.source.audio.muted ? "" : ""
    badgeText: recordingCount > 0 ? countGlyph(recordingCount) : ""
    smoothTextColor: false
    textColor: recordingCount ? shell.alpha(shell.role("error", shell.foreground), .25 + blink.phase * .75) : shell.foreground
    tooltip: !root.source ? "No input device"
        : "Input level: " + Math.round(root.source.audio.volume * 100) + "%"
            + (root.source.audio.muted ? " (muted)" : "")
            + "\nUsing: " + (root.source.description || root.source.nickname || root.source.name)
    onClicked: button => button === Qt.RightButton
        ? (source ? source.audio.muted = !source.audio.muted : false)
        : shell.togglePopup("microphone")

    PwObjectTracker { objects: [root.source].filter(x => x) }
    SequentialAnimation {
        id: blink
        property real phase: 0
        running: root.recordingCount > 0; loops: Animation.Infinite
        NumberAnimation { target: blink; property: "phase"; from: 0; to: 1; duration: 600 }
        NumberAnimation { target: blink; property: "phase"; from: 1; to: 0; duration: 600 }
    }
    AudioPopup { anchorItem: root; shell: root.shell; microphoneMode: true; popupEnabled: root.popupEnabled }
}

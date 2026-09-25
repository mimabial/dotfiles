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
    radius: shell.moduleRadius
    text: !root.source || root.source.audio.muted ? "" : ""
    tooltip: !root.source ? "No input device"
        : "Input level: " + Math.round(root.source.audio.volume * 100) + "%"
            + (root.source.audio.muted ? " (muted)" : "")
            + "\nUsing: " + (root.source.description || root.source.nickname || root.source.name)
    onClicked: button => button === Qt.RightButton
        ? (source ? source.audio.muted = !source.audio.muted : false)
        : shell.togglePopup("microphone")

    PwObjectTracker { objects: [root.source].filter(x => x) }
    Rectangle {
        visible: root.recordingCount > 0
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: -Style.xxs; anchors.rightMargin: -Style.xxs
        height: Style.px(12); width: Math.max(height, badge.implicitWidth + Style.sm)
        radius: height / 2; color: root.shell.urgent
        Text { id: badge; anchors.centerIn: parent; text: String(root.recordingCount); color: root.shell.background; font.family: root.shell.fontFamily; font.pixelSize: Style.px(9); font.bold: true }
    }
    AudioPopup { anchorItem: root; shell: root.shell; microphoneMode: true; popupEnabled: root.popupEnabled }
}

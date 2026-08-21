import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var captures: Pipewire.nodes.values.filter(node => node.isStream && ((node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream || (node.type & PwNodeType.Video) === PwNodeType.Video))
    readonly property bool shown: captures.length > 0
    visible: shown
    css: "privacy"
    text: captures.some(node => (node.type & PwNodeType.Video) === PwNodeType.Video) ? "󰄀" : "󰍬"
    property real blinkPhase: 0
    smoothTextColor: false
    textColor: shell.alpha(shell.role("error", shell.foreground), .25 + blinkPhase * .75)
    SequentialAnimation on blinkPhase {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 600 }
        NumberAnimation { from: 1; to: 0; duration: 600 }
    }
    tooltip: "Privacy: " + captures.map(node => node.description || node.name).join(", ")
}

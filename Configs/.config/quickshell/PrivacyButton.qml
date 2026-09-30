import QtQuick

BarButton {
    id: root
    readonly property bool shown: Privacy.screen.length > 0
    visible: shown
    css: "privacy"
    text: Privacy.screen.some(node => Privacy.isVideo(node)) ? "\u{f1483}" : "\u{f036c}"
    property real blinkPhase: 0
    smoothTextColor: false
    textColor: shell.alpha(shell.role("error", shell.foreground), .25 + blinkPhase * .75)
    SequentialAnimation on blinkPhase {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 600 }
        NumberAnimation { from: 1; to: 0; duration: 600 }
    }
    tooltip: "Other capture: " + Privacy.screen.map(node => node.description || node.name).join(", ")
}

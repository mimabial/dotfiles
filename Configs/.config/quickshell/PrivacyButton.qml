import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var captureNodes: Pipewire.nodes.values.filter(node =>
        (node.type & PwNodeType.Video) === PwNodeType.Video
        || (node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream)
    PwObjectTracker { objects: root.captureNodes }

    function ignored(node) {
        const props = node.properties
        return String(props["quickshell.privacy.ignore"]) === "true"
            || String(props["stream.capture.sink"]) === "true"
    }
    function cameraStream(node) {
        return node.properties["media.role"] === "Camera"
            || Pipewire.linkGroups.values.some(group => group.target === node && group.source
                && group.source.properties["media.role"] === "Camera")
    }
    function microphoneStream(node) {
        return Pipewire.linkGroups.values.some(group => group.target === node && group.source
            && !group.source.isStream && !group.source.isSink
            && !String(group.source.name).endsWith(".monitor"))
    }
    readonly property var captures: captureNodes.filter(node => {
        if (!node.ready || root.ignored(node)) return false
        if ((node.type & PwNodeType.Video) === PwNodeType.Video)
            return node.isStream ? !root.cameraStream(node)
                : node.properties["media.role"] === "Screen"
                    && Pipewire.linkGroups.values.some(group => group.source === node)
        return !root.microphoneStream(node)
    })
    readonly property bool shown: captures.length > 0
    visible: shown
    css: "privacy"
    text: captures.some(node => (node.type & PwNodeType.Video) === PwNodeType.Video) ? "\u{f1483}" : "\u{f036c}"
    property real blinkPhase: 0
    smoothTextColor: false
    textColor: shell.alpha(shell.role("error", shell.foreground), .25 + blinkPhase * .75)
    SequentialAnimation on blinkPhase {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 600 }
        NumberAnimation { from: 1; to: 0; duration: 600 }
    }
    tooltip: "Other capture: " + captures.map(node => node.description || node.name).join(", ")
}

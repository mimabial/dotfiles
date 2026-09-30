pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root
    readonly property var captureNodes: Pipewire.nodes.values.filter(node => isVideo(node)
        || (node.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream)
    readonly property var active: captureNodes.filter(node => node.ready && !ignored(node))
    readonly property var camera: active.filter(node => isVideo(node) && node.isStream && cameraStream(node))
    readonly property var microphone: active.filter(node => !isVideo(node) && microphoneStream(node))
    readonly property var screen: active.filter(node => !isVideo(node) ? !microphoneStream(node)
        : node.isStream ? !cameraStream(node)
        : node.properties["media.role"] === "Screen" && Pipewire.linkGroups.values.some(group => group.source === node))
    property PwObjectTracker tracker: PwObjectTracker { objects: root.captureNodes }
    property bool location: false
    property Process locationWatch: Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.GeoClue2", "--object-path", "/org/freedesktop/GeoClue2/Manager"]
        stdout: SplitParser { onRead: line => { const inUse = line.match(/'InUse': <(true|false)>/); if (inUse) root.location = inUse[1] === "true" } }
    }
    property Process locationProbe: Process {
        running: true
        command: ["sh", "-c", "gdbus call --system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner org.freedesktop.GeoClue2 | grep -q true"
            + " && gdbus call --system --dest org.freedesktop.GeoClue2 --object-path /org/freedesktop/GeoClue2/Manager --method org.freedesktop.DBus.Properties.Get org.freedesktop.GeoClue2.Manager InUse"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.location = text.includes("true") }
    }

    function isVideo(node) { return (node.type & PwNodeType.Video) === PwNodeType.Video }
    function appName(node) { return node.properties["application.name"] || node.description || node.name }
    function ignored(node) {
        const props = node.properties
        return String(props["quickshell.privacy.ignore"]) === "true" || String(props["stream.capture.sink"]) === "true"
    }
    function cameraStream(node) {
        return node.properties["media.role"] === "Camera"
            || Pipewire.linkGroups.values.some(group => group.target === node && group.source
                && group.source.properties["media.role"] === "Camera")
    }
    function microphoneStream(node) {
        return Pipewire.linkGroups.values.some(group => group.target === node && group.source
            && !group.source.isStream && !group.source.isSink && !String(group.source.name).endsWith(".monitor"))
    }
}

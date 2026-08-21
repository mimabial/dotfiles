import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    property bool popupEnabled: true
    property bool framed: true
    // the fa device glyphs are double-width in a mono advance; that key adds
    // the right padding that recentres them
    css: root.portIcon !== "" && !(root.sink && root.sink.audio.muted) ? "pulseaudio.headphone" : "pulseaudio"
    radius: shell.moduleRadius
    fill: framed ? shell.alpha(shell.background, .1) : "transparent"
    outline: shell.alpha(shell.role("br", shell.foreground), .3)
    // waybar's pulseaudio format-icons, in its declared order: a matching
    // port wins over the volume ramp, mute wins over both. waybar reads the
    // active port name; quickshell's pipewire API exposes no port, so this
    // matches the node properties that carry the same words
    readonly property var portIcons: [
        ["headphone", ""], ["hands-free", ""], ["headset", ""],
        ["phone", ""], ["portable", ""], ["car", ""]
    ]
    // the active port is the only thing that tracks the analog jack, and
    // pipewire does not expose it — waybar reads it from pulse directly
    property string activePort: ""
    function probePort() { if (!portProbe.running) portProbe.running = true }
    function clampVolume() { if (sink && sink.audio && sink.audio.volume > shell.volumeLimit) sink.audio.volume = shell.volumeLimit }
    onSinkChanged: { probePort(); shell.refreshVolumeRange(); clampVolume() }
    onActivePortChanged: shell.refreshVolumeRange()

    readonly property string portIcon: {
        const props = root.sink ? root.sink.properties : null
        const port = root.activePort.toLowerCase()
        // exact on the properties: "audio-card-analog" contains "car".
        // substring on the port, as waybar does: "analog-output-headphones"
        const factor = props ? String(props["device.form_factor"] || "").toLowerCase() : ""
        const iconName = props ? String(props["device.icon-name"] || "").toLowerCase() : ""
        for (let i = 0; i < portIcons.length; ++i) {
            const key = portIcons[i][0]
            if (port.includes(key) || factor === key
                || iconName === "audio-" + key || iconName === "audio-" + key + "s")
                return portIcons[i][1]
        }
        return ""
    }

    Process {
        id: portProbe
        command: ["pactl", "--format=json", "list", "sinks"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const name = root.sink ? root.sink.name : ""
                const found = JSON.parse(text).find(entry => entry.name === name)
                root.activePort = found ? String(found.active_port || "") : ""
            } catch (error) { root.activePort = "" }
        } }
    }
    // only changes when something is physically plugged in
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.probePort() }
    readonly property string volumeIcon: !root.sink ? "󰕾" : root.sink.audio.volume < .34 ? "󰕿"
        : root.sink.audio.volume < .67 ? "󰖀" : "󰕾"
    text: !root.sink || root.sink.audio.muted ? "󰝟" : root.portIcon || root.volumeIcon
    onClicked: button => button === Qt.RightButton ? (sink ? sink.audio.muted = !sink.audio.muted : false) : shell.togglePopup("audio")
    onWheeled: delta => { if (sink) sink.audio.volume = Math.max(0, Math.min(shell.volumeLimit, sink.audio.volume + (delta > 0 ? .05 : -.05))) }

    PwObjectTracker { objects: [root.sink].filter(x => x) }
    Connections { target: root.sink ? root.sink.audio : null; function onVolumeChanged() { root.clampVolume() } }
    Connections { target: root.shell; function onVolumeLimitChanged() { root.clampVolume() } }
    AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

import QtQuick
import Quickshell.Services.Pipewire

BarButton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    property bool popupEnabled: true
    property string popupName: "audio"
    property bool framed: true
    readonly property bool muted: root.sink ? root.sink.audio.muted : false
    css: "volume" + (root.muted ? ".muted" : "")
    // must measure the face BarButton draws with, or the nudge corrects an ink
    // overhang the drawn glyph does not have
    TextMetrics { id: iconMetrics; font.family: root.usesIconFont ? root.shell.iconGlyphFont : root.shell.fontFamily; font.pixelSize: root.renderedFontSize; font.weight: root.fontWeight; text: root.text }
    textOffsetX: fitsIconBox ? inkOffsetX : iconMetrics.advanceWidth / 2 - iconMetrics.tightBoundingRect.x - iconMetrics.tightBoundingRect.width / 2
    backgroundColor: framed ? root.styleColor("backgroundColor") : "transparent"
    // pulseaudio format-icons, in their declared order: a matching port wins
    // over the volume ramp, mute wins over both. The selection keys off the
    // active port name; quickshell's pipewire API exposes no port, so this
    // matches the node properties that carry the same words
    readonly property var portIcons: [
        ["headphone", "󱡏"], ["hands-free", "󱡏"], ["headset", "󱡏"],
        ["phone", "󰏲"], ["portable", "󰏲"], ["car", "󰄋"]
    ]
    // the active port is the only thing that tracks the analog jack, and
    // pipewire does not expose it — it has to come from pulse directly
    readonly property string activePort: AudioPorts.port(root.sink ? root.sink.name : "")
    function clampVolume() { if (sink && sink.audio && sink.audio.volume > shell.volumeLimit) sink.audio.volume = shell.volumeLimit }
    function volumeAction(action) { shell.run(["hyprshell", "volume-control.sh", "-o", action]) }
    onSinkChanged: { shell.refreshVolumeRange(); clampVolume() }
    onActivePortChanged: shell.refreshVolumeRange()

    readonly property string portKey: {
        const props = root.sink ? root.sink.properties : null
        const port = root.activePort.toLowerCase()
        // exact on the properties: "audio-card-analog" contains "car".
        // substring on the port: "analog-output-headphones"
        const factor = props ? String(props["device.form_factor"] || "").toLowerCase() : ""
        const iconName = props ? String(props["device.icon-name"] || "").toLowerCase() : ""
        for (let i = 0; i < portIcons.length; ++i) {
            const key = portIcons[i][0]
            if (port.includes(key) || factor === key
                || iconName === "audio-" + key || iconName === "audio-" + key + "s")
                return key
        }
        return ""
    }
    readonly property string portIcon: { const hit = portIcons.find(entry => entry[0] === root.portKey); return hit ? hit[1] : "" }
    readonly property string mutedPortIcon: ["headphone", "hands-free", "headset"].includes(root.portKey) ? "󱡒" : ""

    readonly property bool zeroVolume: root.sink ? Math.round(root.sink.audio.volume * 100) === 0 : false
    text: !root.sink || root.muted ? "\uEB24" : "\uEB75"
    tooltip: !root.sink ? "No output device"
        : "Volume level: " + Math.round(root.sink.audio.volume * 100) + "%" + (root.portKey ? " " + root.portKey : "")
            + "\nUsing: " + (root.sink.description || root.sink.nickname || root.sink.name)
    onClicked: button => button === Qt.RightButton ? (sink ? root.volumeAction("m") : false) : shell.togglePopup(popupName)
    onWheeled: delta => { if (sink) root.volumeAction(delta > 0 ? "i" : "d") }

    PwObjectTracker { objects: [root.sink].filter(x => x) }
    Connections { target: root.sink ? root.sink.audio : null; function onVolumeChanged() { root.clampVolume() } }
    Connections { target: root.shell; function onVolumeLimitChanged() { root.clampVolume() } }
    AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

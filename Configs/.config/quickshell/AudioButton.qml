import QtQuick
import Quickshell.Services.Pipewire
import "modules/StatusSymbols.js" as StatusSymbols

BarButton {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    property bool popupEnabled: true
    property string popupName: "audio"
    property string settingsPopupName: popupName
    property bool framed: true
    readonly property bool muted: root.sink ? root.sink.audio.muted : false
    css: "volume" + (root.muted ? ".muted" : "")
    symbol: root.styledSymbol ? StatusSymbols.volume(root.sink, root.muted) : ""
    TextMetrics { id: drawnGlyphMetrics; font.family: root.usesIconFont ? root.shell.iconGlyphFont : root.shell.fontFamily; font.pixelSize: root.renderedFontSize; font.weight: root.fontWeight; text: root.text }
    textOffsetX: fitsIconBox ? inkOffsetX : drawnGlyphMetrics.advanceWidth / 2 - drawnGlyphMetrics.tightBoundingRect.x - drawnGlyphMetrics.tightBoundingRect.width / 2
    backgroundColor: framed ? root.styleColor("backgroundColor") : "transparent"
    readonly property var portIcons: [
        ["headphone", "󱡏"], ["hands-free", "󱡏"], ["headset", "󱡏"],
        ["phone", "󰏲"], ["portable", "󰏲"], ["car", "󰄋"]
    ]
    readonly property string activePort: AudioPorts.port(root.sink ? root.sink.name : "")
    function clampVolume() { if (sink && sink.audio && sink.audio.volume > shell.volumeLimit) sink.audio.volume = shell.volumeLimit }
    function volumeAction(action) { shell.run(["hyprshell", "volume-control.sh", "-o", action]) }
    onSinkChanged: { shell.refreshVolumeRange(); clampVolume() }
    onActivePortChanged: shell.refreshVolumeRange()

    readonly property string portKey: {
        const sinkProperties = root.sink ? root.sink.properties : null
        const port = root.activePort.toLowerCase()
        const formFactor = sinkProperties ? String(sinkProperties["device.form_factor"] || "").toLowerCase() : ""
        const iconName = sinkProperties ? String(sinkProperties["device.icon-name"] || "").toLowerCase() : ""
        for (let i = 0; i < portIcons.length; ++i) {
            const key = portIcons[i][0]
            if (port.includes(key) || formFactor === key
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
    AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; popupName: root.settingsPopupName }
}

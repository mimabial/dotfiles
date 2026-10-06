pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import ".."

AudioButton {
    id: root
    property bool popupsAllowed: true
    property bool mediaCard: false
    readonly property var devices: Pipewire.nodes.values.filter(node => node?.audio && !node.isStream)
    readonly property var inputs: devices.filter(node => !node.isSink)
    popupName: "sound-menu"; popupEnabled: popupsAllowed
    text: !sink ? "󰖁" : muted ? mutedPortIcon || "󰝟" : portIcon && !zeroVolume ? portIcon
        : (sink.audio?.volume ?? 0) < .34 ? "󰕿" : sink.audio.volume < .67 ? "󰖀" : "󰕾"
    symbolContext: ["headphone", "headset", "hands-free"].includes(portKey) && !muted ? "devices" : "status"
    symbol: !sink || muted ? "audio-volume-muted" : symbolContext === "devices" ? "audio-headphones"
        : (sink.audio?.volume ?? 0) < .34 ? "audio-volume-low" : sink.audio.volume < .67 ? "audio-volume-medium" : "audio-volume-high"
    function deviceIcon(node) { return node.name.startsWith("bluez") ? "󰋋" : /hdmi|displayport/i.test(node.name) ? "󰍹" : node.isSink ? "󰓃" : "󰍬" }
    component Device: PopupRow {
        required property var modelData
        required property var current
        width: parent.width; shell: root.shell; icon: root.deviceIcon(modelData)
        title: modelData.description || modelData.nickname || modelData.name
        iconColor: modelData === current ? root.shell.accent : root.shell.alpha(root.shell.foreground, .55)
    }
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "sound-menu"; settings: "Sound"; settingsPopup: "audio"
        Column {
            width: parent.width; spacing: Style.xs; visible: root.mediaCard
            PopupRow {
                width: parent.width; shell: root.shell; visible: Media.hasMedia
                iconSource: Media.artUrl; icon: Media.artUrl ? "" : "󰝚"; iconSize: Style.controlHeight
                title: Media.title; detail: Media.artist; rightInset: mediaControls.width + Style.sm
                onClicked: root.shell.togglePopup("media")
                Row {
                    id: mediaControls
                    anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.xs
                    PopupIconButton { shell: root.shell; glyph: "󰒮"; hint: "Previous"; enabled: !!Media.player?.canGoPrevious; glyphColor: enabled ? shell.foreground : shell.faintText; onClicked: Media.previous() }
                    PopupIconButton { shell: root.shell; glyph: Media.player?.isPlaying ? "󰏤" : "󰐊"; hint: Media.player?.isPlaying ? "Pause" : "Play"; enabled: !!(Media.player?.canPlay || Media.player?.canPause || Media.player?.canTogglePlaying); onClicked: Media.playPause() }
                    PopupIconButton { shell: root.shell; glyph: "󰒭"; hint: "Next"; enabled: Media.canNext(); glyphColor: enabled ? shell.foreground : shell.faintText; onClicked: Media.next() }
                }
            }
            PopupRow { width: parent.width; shell: root.shell; title: "Open CLIamp…"; onClicked: root.shell.togglePopup("media") }
            PopupSeparator { shell: root.shell }
        }
        PopupSlider {
            width: parent.width; shell: root.shell; label: "Sound"; maximum: root.shell.volumeLimit
            value: root.sink?.audio?.volume ?? 0
            onChanged: value => { if (root.sink?.audio) root.sink.audio.volume = value }
        }
        PopupSection { shell: root.shell; text: "OUTPUT" }
        Repeater {
            model: root.devices.filter(node => node.isSink)
            Device { id: output; current: root.sink; onClicked: Pipewire.preferredDefaultAudioSink = output.modelData }
        }
        PopupSection { shell: root.shell; text: "INPUT"; visible: root.inputs.length > 1 }
        Repeater {
            model: root.inputs.length > 1 ? root.inputs : []
            Device { id: input; current: Pipewire.defaultAudioSource; onClicked: Pipewire.preferredDefaultAudioSource = input.modelData }
        }
    }
    LazyPopup {
        shell: root.shell; popup: "media"; owners: ["mediaplayer", "nowplaying"]; popupsAllowed: root.mediaCard && root.popupsAllowed
        sourceComponent: Component { MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.mediaCard && root.popupsAllowed } }
    }
}

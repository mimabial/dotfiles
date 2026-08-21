import QtQuick
import Quickshell.Services.Pipewire

PopupCard {
    id: root
    popupName: "audio"
    contentWidth: 380
    contentHeight: 660
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(node => node && node.isSink && !node.isStream && node.audio)
    readonly property var streams: nodes.filter(node => node && node.isSink && node.isStream && node.audio)
    readonly property var inputs: nodes.filter(node => node && !node.isSink && !node.isStream && node.audio)
    function name(node) { return node ? node.description || node.nickname || node.name || "Audio device" : "Unavailable" }
    property PwObjectTracker tracker: PwObjectTracker { objects: root.nodes.filter(node => node && node.audio) }

    Column {
        anchors.fill: parent; spacing: 14
        PopupSection { shell: root.shell; text: "AUDIO" }
        PopupRow { width: parent.width; shell: root.shell; icon: root.sink && root.sink.audio && root.sink.audio.muted ? "󰝟" : "󰕾"; title: root.name(root.sink); detail: "Output"; value: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : ""; active: root.sink && root.sink.audio && !root.sink.audio.muted; onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
        PopupSlider { width: parent.width; shell: root.shell; label: "Output volume"; value: root.sink && root.sink.audio ? root.sink.audio.volume : 0; maximum: root.shell.volumeLimit; onChanged: value => { if (root.sink && root.sink.audio) root.sink.audio.volume = value } }
        PopupSlider { width: parent.width; shell: root.shell; label: "Volume limit"; value: root.shell.volumeToDb(root.shell.volumeLimit); valueText: (value > 0 ? "+" : "") + value.toFixed(2).replace(/\.?0+$/, "") + " dB"; minimum: root.shell.volumeMinDb; maximum: root.shell.volumeMaxDb; step: root.shell.volumeStepDb; onChanged: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), false); onReleased: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), true) }
        PopupRow { visible: root.source !== null; width: parent.width; shell: root.shell; icon: root.source && root.source.audio && root.source.audio.muted ? "󰍭" : "󰍬"; title: root.name(root.source); detail: "Microphone"; value: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) + "%" : ""; active: root.source && root.source.audio && !root.source.audio.muted; onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted }
        PopupSlider { visible: root.source !== null; width: parent.width; shell: root.shell; label: "Input volume"; value: root.source && root.source.audio ? root.source.audio.volume : 0; onChanged: value => { if (root.source && root.source.audio) root.source.audio.volume = value } }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "OUTPUT DEVICE" }
        ListView {
            width: parent.width; height: Math.min(contentHeight, 85); spacing: 4; clip: true; model: root.outputs
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰓃"; title: root.name(modelData); detail: modelData === root.sink ? "Default" : ""; active: modelData === root.sink; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
        }
        PopupSeparator { visible: root.inputs.length > 0; shell: root.shell }
        PopupSection { visible: root.inputs.length > 0; shell: root.shell; text: "INPUT DEVICE" }
        ListView {
            visible: root.inputs.length > 0
            width: parent.width; height: Math.min(contentHeight, 85); spacing: 4; clip: true; model: root.inputs
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰍬"; title: root.name(modelData); detail: modelData === root.source ? "Default" : ""; active: modelData === root.source; onClicked: Pipewire.preferredDefaultAudioSource = modelData }
        }
        PopupSeparator { shell: root.shell }
        PopupSection { visible: root.streams.length > 0; shell: root.shell; text: "APPLICATIONS" }
        ListView {
            visible: root.streams.length > 0; width: parent.width; height: Math.min(contentHeight, 88); spacing: 4; clip: true; model: root.streams
            delegate: PopupSlider { required property var modelData; width: ListView.view.width; shell: root.shell; label: root.name(modelData); value: modelData.audio.volume; onChanged: value => modelData.audio.volume = value }
        }
    }
}

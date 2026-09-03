pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

PopupCard {
    id: root
    popupName: "audio"
    contentWidth: Style.px(380)
    contentHeight: audioColumn.implicitHeight + padding * 2
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(node => node && node.isSink && !node.isStream && node.audio)
    readonly property var streams: nodes.filter(node => node && node.isSink && node.isStream && node.audio)
    readonly property var inputs: nodes.filter(node => node && !node.isSink && !node.isStream && node.audio)
    function name(node) { return node ? node.description || node.nickname || node.name || "Audio device" : "Unavailable" }
    function volumeAction(device, action) { root.shell.run(["hyprshell", "volume-control.sh", "-" + device, action]) }
    function adjustCursor(direction) {
        rebuildRows()
        if (cursorIndex >= 0 && cursorIndex < navigableRows.length) {
            const item = navigableRows[cursorIndex]
            if (item.adjustKeyboard) {
                item.adjustKeyboard(direction)
                return true
            }
        }
        if (root.sink) {
            volumeAction("o", direction > 0 ? "i" : "d")
            return true
        }
        return false
    }
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_J: moveCursor(1); return true
        case Qt.Key_K: moveCursor(-1); return true
        case Qt.Key_H:
        case Qt.Key_Left: return adjustCursor(-1)
        case Qt.Key_L:
        case Qt.Key_Right: return adjustCursor(1)
        case Qt.Key_Space: activateCursor(); return true
        case Qt.Key_M: if (root.sink) volumeAction("o", "m"); return true
        case Qt.Key_I: if (root.source) volumeAction("i", "m"); return true
        }
        return defaultKey(event)
    }
    function volumeName() {
        const audio = root.sink && root.sink.audio
        if (!audio) return "no output"
        if (audio.muted) return "muted"
        const steps = [[100, "concert hall"], [85, "party mode"], [70, "cranked up"], [50, "steady groove"], [30, "easy listening"], [15, "murmur"], [1, "whisper"]]
        for (const [floor, name] of steps) if (Math.round(audio.volume * 100) >= floor) return name
        return "silenced"
    }
    property PwObjectTracker tracker: PwObjectTracker { objects: root.nodes.filter(node => node && node.audio) }

    Column {
        id: audioColumn
        anchors.fill: parent; spacing: Style.px(14)
        PopupHero { shell: root.shell; title: "Audio"; status: root.volumeName() }
        PopupSeparator { shell: root.shell }
        PopupRow { width: parent.width; shell: root.shell; icon: root.sink && root.sink.audio && root.sink.audio.muted ? "󰝟" : "󰕾"; title: root.name(root.sink); detail: "Output"; value: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : ""; active: root.sink && root.sink.audio && !root.sink.audio.muted; onClicked: if (root.sink) root.volumeAction("o", "m") }
        PopupSlider { width: parent.width; shell: root.shell; label: "Output volume"; keyboardEnabled: root.sink !== null; keyboardAdjustsExternally: true; value: root.sink && root.sink.audio ? root.sink.audio.volume : 0; maximum: root.shell.volumeLimit; onChanged: value => { if (root.sink && root.sink.audio) root.sink.audio.volume = value }; onKeyboardAdjusted: direction => root.volumeAction("o", direction > 0 ? "i" : "d") }
        PopupSlider { width: parent.width; shell: root.shell; label: "Volume limit"; keyboardEnabled: true; value: root.shell.volumeToDb(root.shell.volumeLimit); valueText: (value > 0 ? "+" : "") + value.toFixed(2).replace(/\.?0+$/, "") + " dB"; minimum: root.shell.volumeMinDb; maximum: root.shell.volumeMaxDb; step: root.shell.volumeStepDb; onChanged: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), false); onReleased: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), true) }
        PopupRow { visible: root.source !== null; width: parent.width; shell: root.shell; icon: root.source && root.source.audio && root.source.audio.muted ? "󰍭" : "󰍬"; title: root.name(root.source); detail: "Microphone"; value: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) + "%" : ""; active: root.source && root.source.audio && !root.source.audio.muted; onClicked: if (root.source) root.volumeAction("i", "m") }
        PopupSlider { visible: root.source !== null; width: parent.width; shell: root.shell; label: "Input volume"; keyboardEnabled: true; keyboardAdjustsExternally: true; value: root.source && root.source.audio ? root.source.audio.volume : 0; onChanged: value => { if (root.source && root.source.audio) root.source.audio.volume = value }; onKeyboardAdjusted: direction => root.volumeAction("i", direction > 0 ? "i" : "d") }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "OUTPUT DEVICE" }
        ListView {
            width: parent.width; height: Math.min(contentHeight, Style.px(85)); spacing: Style.px(4); clip: true; model: root.outputs
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰓃"; title: root.name(modelData); detail: modelData === root.sink ? "Default" : ""; active: modelData === root.sink; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
        }
        PopupSeparator { visible: root.inputs.length > 0; shell: root.shell }
        PopupSection { visible: root.inputs.length > 0; shell: root.shell; text: "INPUT DEVICE" }
        ListView {
            visible: root.inputs.length > 0
            width: parent.width; height: Math.min(contentHeight, Style.px(85)); spacing: Style.px(4); clip: true; model: root.inputs
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰍬"; title: root.name(modelData); detail: modelData === root.source ? "Default" : ""; active: modelData === root.source; onClicked: Pipewire.preferredDefaultAudioSource = modelData }
        }
        PopupSeparator { shell: root.shell }
        PopupSection { visible: root.streams.length > 0; shell: root.shell; text: "APPLICATIONS" }
        ListView {
            visible: root.streams.length > 0; width: parent.width; height: Math.min(contentHeight, Style.px(88)); spacing: Style.px(4); clip: true; model: root.streams
            delegate: PopupSlider { required property var modelData; width: ListView.view.width; shell: root.shell; keyboardEnabled: true; label: root.name(modelData); value: modelData.audio.volume; onChanged: value => modelData.audio.volume = value }
        }
        Text { width: parent.width; text: "j/k navigate  ·  h/l adjust  ·  m output mute  ·  i mic mute"; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter }
    }
}

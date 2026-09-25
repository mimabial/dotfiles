pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

PopupCard {
    id: root
    property bool microphoneMode: false
    popupName: microphoneMode ? "microphone" : "audio"
    contentWidth: Style.px(380)
    contentHeight: audioColumn.implicitHeight + padding * 2
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var activeNode: microphoneMode ? source : sink
    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(node => node && node.isSink && !node.isStream && node.audio)
    readonly property var playbacks: nodes.filter(node => node && node.isStream && !node.isSink && node.audio)
    readonly property var recordings: nodes.filter(node => node && node.isStream && node.isSink && node.audio)
    readonly property var inputs: nodes.filter(node => node && !node.isSink && !node.isStream && node.audio)
    function name(node) { return node ? node.description || node.nickname || node.name || "Audio device" : "Unavailable" }
    function target(stream) {
        const link = Pipewire.linkGroups.values.find(group => stream.isSink ? group.target === stream : group.source === stream)
        return link ? (stream.isSink ? link.source : link.target) : null
    }
    function route(stream, device) {
        const command = ["pw-metadata", "-n", "default", "--", String(stream.id), "target.object", device ? device.name : "-1"]
        if (!device) command.push("Spa:Id")
        root.shell.run(command)
    }
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
        if (root.activeNode) {
            volumeAction(root.microphoneMode ? "i" : "o", direction > 0 ? "i" : "d")
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
        case Qt.Key_M: if (root.activeNode) volumeAction(root.microphoneMode ? "i" : "o", "m"); return true
        case Qt.Key_I: if (root.microphoneMode && root.source) volumeAction("i", "m"); return true
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
    function microphoneStatus() { return !root.source ? "unavailable" : root.source.audio.muted ? "muted" : root.recordings.length ? "in use" : "ready" }
    property PwObjectTracker tracker: PwObjectTracker { objects: root.open ? (root.microphoneMode ? root.inputs.concat(root.recordings) : root.outputs.concat(root.playbacks)) : [] }

    component StreamControl: Column {
        id: control
        required property var stream
        property bool recording: false
        readonly property var devices: recording ? root.inputs : root.outputs
        width: ListView.view.width
        spacing: Style.xs
        PopupRow {
            width: parent.width; shell: root.shell
            icon: control.stream.audio.muted ? "󰝟" : control.recording ? "󰍬" : "󰕾"
            title: root.name(control.stream)
            detail: (control.recording ? "Recording from " : "Playing on ") + root.name(root.target(control.stream))
            value: Math.round(control.stream.audio.volume * 100) + "%"
            onClicked: control.stream.audio.muted = !control.stream.audio.muted
        }
        PopupSlider {
            width: parent.width; shell: root.shell; keyboardEnabled: true
            label: control.recording ? "Capture gain" : "App volume"
            value: control.stream.audio.volume
            onChanged: value => control.stream.audio.volume = value
        }
        PopupSelect {
            id: routeSelect
            width: parent.width; shell: root.shell
            choices: [{label: "Route to device…"}, {label: "Follow default"}].concat(control.devices.map(device => ({label: root.name(device)})))
            onActivated: index => {
                if (index > 0) root.route(control.stream, index === 1 ? null : control.devices[index - 2])
                routeSelect.currentIndex = 0
            }
        }
    }

    Column {
        id: audioColumn
        anchors.fill: parent; spacing: Style.px(14)
        PopupHero { shell: root.shell; title: root.microphoneMode ? "Microphone" : "Audio"; status: root.microphoneMode ? root.microphoneStatus() : root.volumeName() }
        PopupSeparator { shell: root.shell }
        PopupRow { visible: !root.microphoneMode; width: parent.width; shell: root.shell; icon: root.sink && root.sink.audio && root.sink.audio.muted ? "󰝟" : "󰕾"; title: root.name(root.sink); detail: "Output"; value: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : ""; active: root.sink && root.sink.audio && !root.sink.audio.muted; onClicked: if (root.sink) root.volumeAction("o", "m") }
        PopupSlider { visible: !root.microphoneMode; width: parent.width; shell: root.shell; label: "Output volume"; keyboardEnabled: root.sink !== null; keyboardAdjustsExternally: true; value: root.sink && root.sink.audio ? root.sink.audio.volume : 0; maximum: root.shell.volumeLimit; onChanged: value => { if (root.sink && root.sink.audio) root.sink.audio.volume = value }; onKeyboardAdjusted: direction => root.volumeAction("o", direction > 0 ? "i" : "d") }
        PopupSlider { visible: !root.microphoneMode; width: parent.width; shell: root.shell; label: "Volume limit"; keyboardEnabled: true; value: root.shell.volumeToDb(root.shell.volumeLimit); valueText: (value > 0 ? "+" : "") + value.toFixed(2).replace(/\.?0+$/, "") + " dB"; minimum: root.shell.volumeMinDb; maximum: root.shell.volumeMaxDb; step: root.shell.volumeStepDb; onChanged: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), false); onReleased: value => root.shell.setVolumeLimit(root.shell.dbToVolume(value), true) }
        PopupRow { visible: root.microphoneMode && root.source !== null; width: parent.width; shell: root.shell; icon: root.source && root.source.audio && root.source.audio.muted ? "󰍭" : "󰍬"; title: root.name(root.source); detail: "Microphone"; value: root.source && root.source.audio ? Math.round(root.source.audio.volume * 100) + "%" : ""; active: root.source && root.source.audio && !root.source.audio.muted; onClicked: if (root.source) root.volumeAction("i", "m") }
        PopupSlider { visible: root.microphoneMode && root.source !== null; width: parent.width; shell: root.shell; label: "Input volume"; keyboardEnabled: true; keyboardAdjustsExternally: true; value: root.source && root.source.audio ? root.source.audio.volume : 0; onChanged: value => { if (root.source && root.source.audio) root.source.audio.volume = value }; onKeyboardAdjusted: direction => root.volumeAction("i", direction > 0 ? "i" : "d") }
        PopupSeparator { shell: root.shell }
        PopupSection { visible: !root.microphoneMode; shell: root.shell; text: "OUTPUT DEVICE" }
        ListView {
            visible: !root.microphoneMode; width: parent.width; height: Math.min(contentHeight, Style.px(85)); spacing: Style.px(4); clip: true; model: root.microphoneMode ? [] : root.outputs
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰓃"; title: root.name(modelData); detail: modelData === root.sink ? "Default" : ""; active: modelData === root.sink; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
        }
        PopupSection { visible: root.microphoneMode && root.inputs.length > 0; shell: root.shell; text: "INPUT DEVICE" }
        ListView {
            visible: root.microphoneMode && root.inputs.length > 0
            width: parent.width; height: Math.min(contentHeight, Style.px(85)); spacing: Style.px(4); clip: true; model: root.microphoneMode ? root.inputs : []
            delegate: PopupRow { required property var modelData; width: ListView.view.width; shell: root.shell; icon: "󰍬"; title: root.name(modelData); detail: modelData === root.source ? "Default" : ""; active: modelData === root.source; onClicked: Pipewire.preferredDefaultAudioSource = modelData }
        }
        PopupSeparator { visible: root.microphoneMode ? root.recordings.length > 0 : root.playbacks.length > 0; shell: root.shell }
        PopupSection { visible: !root.microphoneMode && root.playbacks.length > 0; shell: root.shell; text: "PLAYBACK APPLICATIONS" }
        ListView {
            visible: !root.microphoneMode && root.playbacks.length > 0; width: parent.width; height: Math.min(contentHeight, Style.px(150)); spacing: Style.sm; clip: true; model: root.microphoneMode ? [] : root.playbacks
            delegate: StreamControl { required property var modelData; stream: modelData }
        }
        PopupSection { visible: root.microphoneMode && root.recordings.length > 0; shell: root.shell; text: "RECORDING APPLICATIONS" }
        ListView {
            visible: root.microphoneMode && root.recordings.length > 0; width: parent.width; height: Math.min(contentHeight, Style.px(150)); spacing: Style.sm; clip: true; model: root.microphoneMode ? root.recordings : []
            delegate: StreamControl { required property var modelData; stream: modelData; recording: true }
        }
        Text { width: parent.width; text: "j/k navigate  ·  h/l adjust  ·  m mute"; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter }
    }
}

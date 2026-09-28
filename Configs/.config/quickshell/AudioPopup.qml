pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

PopupCard {
    id: root
    property bool microphoneMode: false
    popupName: microphoneMode ? "microphone" : "audio"
    keyboardHint: page === "mixer" ? "↑↓/Tab move · ←→ volume · M mute · Enter select · Esc close" : "↑↓/Tab move · Enter select · Esc back"
    contentWidth: Style.px(380)
    contentHeight: page === "mixer" ? audioColumn.implicitHeight + padding * 2 : Style.px(430)
    property string page: "mixer"
    property string selectedCard: ""
    property var audioCards: []
    property var pinnedRoutes: ({})
    property string routeError: ""
    property string profileError: ""
    readonly property var selectedAudioCard: audioCards.find(item => item.name === selectedCard) || null
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
    function serial(node) { return node && node.ready && node.properties ? String(node.properties["object.serial"] || "") : "" }
    function pinned(stream) {
        const id = stream && stream.ready && stream.properties ? String(stream.properties["object.id"] || "") : ""
        return !!pinnedRoutes[id]
    }
    function refreshRoutes() { if (!routesProc.running) routesProc.running = true }
    function route(stream, device, recording, followDefault) {
        if (routeProc.running) return
        const streamSerial = serial(stream)
        const targetSerial = serial(device)
        if (!/^\d+$/.test(streamSerial) || !/^\d+$/.test(targetSerial)) {
            routeError = "The stream or audio device is no longer available."
            return
        }
        routeError = ""
        routeProc.command = ["hyprshell", "controls/stream-route", recording ? "recording" : "playback",
            streamSerial, targetSerial, followDefault ? "default" : "override"]
        routeProc.running = true
    }
    function refreshCards() { if (!cardsProc.running) cardsProc.running = true }
    function openCards() { page = "cards"; profileError = ""; refreshCards() }
    function openProfiles(cardName) { selectedCard = cardName; page = "profiles"; profileError = "" }
    function setProfile(profile) {
        if (!selectedCard || !profile || profileProc.running) return
        profileError = ""
        profileProc.command = ["hyprshell", "bluetooth/audio-profile-transition", selectedCard, profile]
        profileProc.running = true
    }
    function volumeAction(device, action) { root.shell.run(["hyprshell", "volume-control.sh", "-" + device, action]) }
    function adjustCursor(direction) {
        if (page !== "mixer") return false
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
        if (event.key === Qt.Key_Escape && page !== "mixer") {
            if (page === "profiles") openCards()
            else page = "mixer"
            return true
        }
        switch (event.key) {
        case Qt.Key_J: moveCursor(1); return true
        case Qt.Key_K: moveCursor(-1); return true
        case Qt.Key_H:
        case Qt.Key_Left: return adjustCursor(-1)
        case Qt.Key_L:
        case Qt.Key_Right: return adjustCursor(1)
        case Qt.Key_Space: activateCursor(); return true
        case Qt.Key_M: if (page === "mixer" && root.activeNode) volumeAction(root.microphoneMode ? "i" : "o", "m"); return true
        case Qt.Key_I: if (page === "mixer" && root.microphoneMode && root.source) volumeAction("i", "m"); return true
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
    onPageChanged: { clearCursor(); Qt.callLater(() => { rebuildRows(); cursorIndex = navigableRows.length ? 0 : -1 }) }
    onOpenChanged: if (open) { page = "mixer"; routeError = ""; profileError = ""; refreshRoutes() }

    Process {
        id: routeProc
        stderr: StdioCollector { id: routeStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.routeError = String(routeStderr.text || "Could not change the application route.").trim()
            root.refreshRoutes()
        }
    }
    Process {
        id: routesProc
        command: ["hyprshell", "controls/stream-route-status"]
        stdout: StdioCollector { id: routesStdout; waitForEnd: true }
        onExited: code => {
            if (code !== 0) return
            try { root.pinnedRoutes = JSON.parse(String(routesStdout.text || "{}")) }
            catch (error) { root.pinnedRoutes = ({}) }
        }
    }
    Process {
        id: cardsProc
        command: ["hyprshell", "bluetooth/audio-cards"]
        stdout: StdioCollector { id: cardsStdout; waitForEnd: true }
        stderr: StdioCollector { id: cardsStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) { root.profileError = String(cardsStderr.text || "Could not read audio devices.").trim(); return }
            try {
                const parsed = JSON.parse(String(cardsStdout.text || "[]"))
                root.audioCards = Array.isArray(parsed) ? parsed : []
            } catch (error) { root.profileError = "Audio devices returned invalid data." }
        }
    }
    Process {
        id: profileProc
        stderr: StdioCollector { id: profileStderr; waitForEnd: true }
        onExited: code => {
            if (code !== 0) root.profileError = String(profileStderr.text || "Could not change the device profile.").trim()
            root.refreshCards()
        }
    }

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
            detail: (root.pinned(control.stream) ? "Always use " : "Following default · ") + root.name(root.target(control.stream))
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
            enabled: !routeProc.running
            choices: [{label: "Choose route…"}, {label: "Follow default " + (control.recording ? "input" : "output")}]
                .concat(control.devices.map(device => ({label: "Always use " + root.name(device)})))
            onActivated: index => {
                if (index > 0) root.route(control.stream, index === 1
                    ? (control.recording ? root.source : root.sink) : control.devices[index - 2], control.recording, index === 1)
                routeSelect.currentIndex = 0
            }
        }
    }

    Column {
        id: audioColumn
        anchors.fill: parent; visible: root.page === "mixer"; spacing: Style.px(14)
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
        Text { visible: root.routeError !== ""; width: parent.width; text: root.routeError; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.shell.urgent; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰒓"; title: "Device profiles"; detail: "Sound cards and Bluetooth codecs"; onClicked: root.openCards() }
        Text { width: parent.width; text: "j/k navigate  ·  h/l adjust  ·  m mute"; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter }
    }

    Item {
        anchors.fill: parent; visible: root.page === "cards"
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero { shell: root.shell; title: "Audio devices"; status: "profiles" }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to mixer"; onClicked: root.page = "mixer" }
            PopupSeparator { shell: root.shell }
            ListView {
                width: parent.width; height: parent.height - y - cardMessage.height - Style.sectionGap
                model: root.audioCards; spacing: Style.xs; clip: true
                delegate: PopupRow {
                    required property var modelData
                    width: ListView.view.width; shell: root.shell; icon: modelData.bluetooth ? "󰂯" : "󰓃"
                    title: modelData.label; detail: modelData.activeProfile || "No profile"
                    onClicked: root.openProfiles(modelData.name)
                }
            }
            Text {
                id: cardMessage
                width: parent.width; text: root.profileError || (!root.audioCards.length ? "No audio devices available." : "")
                textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: root.shell.urgent
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
        }
    }
    Item {
        anchors.fill: parent; visible: root.page === "profiles"
        Column {
            anchors.fill: parent; spacing: Style.sectionGap
            PopupHero { shell: root.shell; title: root.selectedAudioCard ? root.selectedAudioCard.label : "Audio device"; status: "profile" }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: "Back to devices"; onClicked: root.openCards() }
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "AVAILABLE PROFILES"; value: profileProc.running ? "switching" : "" }
            ListView {
                width: parent.width; height: parent.height - y - profileMessage.height - Style.sectionGap
                model: root.selectedAudioCard ? root.selectedAudioCard.profiles : []; spacing: Style.xs; clip: true
                delegate: PopupRow {
                    required property var modelData
                    width: ListView.view.width; shell: root.shell; icon: "󰓃"
                    title: modelData.label; detail: root.selectedAudioCard && root.selectedAudioCard.activeProfile === modelData.value ? "Active" : ""
                    active: root.selectedAudioCard && root.selectedAudioCard.activeProfile === modelData.value
                    interactive: !profileProc.running
                    onClicked: root.setProfile(modelData.value)
                }
            }
            Text {
                id: profileMessage
                width: parent.width; text: root.profileError || (!root.selectedAudioCard ? "Audio device disconnected." : "Profile changes preserve volume and mute state.")
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.profileError ? root.shell.urgent : root.shell.alpha(root.shell.foreground, .48)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
        }
    }
}

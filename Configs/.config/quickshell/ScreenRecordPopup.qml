import QtQuick
import Quickshell.Io

// Replaces the XDG portal's ScreenCast dialog: the target and audio choices
// are made here, then recording starts through screenrecord.sh's no-portal
// paths (--smart / --window / --region / --output).
PopupCard {
    id: root
    popupName: "screenrecord"
    contentWidth: 320
    contentHeight: recordColumn.implicitHeight + padding * 2

    property var report: ({})
    readonly property bool recording: String(report.class || "") === "recording"

    property string target: "smart"
    property bool desktopAudio: false
    property bool micAudio: false
    property bool webcam: false

    readonly property var targets: [
        {id: "smart",  icon: "\u{f0349}", label: "Smart",   detail: "Click a window or drag"},
        {id: "window", icon: "\u{f05d0}", label: "Window",  detail: "The focused window"},
        {id: "region", icon: "\u{f0c3d}", label: "Region",  detail: "Drag a rectangle"},
        {id: "output", icon: "\u{f0379}", label: "Display", detail: "The whole screen"}
    ]

    function refresh() { if (!statusProc.running) statusProc.running = true }
    function persist() {
        store.setText(JSON.stringify({
            target: target, desktopAudio: desktopAudio, micAudio: micAudio, webcam: webcam
        }))
    }
    function start() {
        const command = ["hyprshell", "screenrecord", "--start", "--" + target]
        if (desktopAudio) command.push("--with-desktop-audio")
        if (micAudio) command.push("--with-microphone-audio")
        if (webcam) command.push("--with-webcam")
        shell.run(command)
        shell.closePopup()
        settle.restart()
    }
    function stop() { shell.run(["hyprshell", "screenrecord", "--quit"]); settle.restart() }

    onOpenChanged: if (open) refresh()

    property Process statusProc: Process {
        command: ["hyprshell", "screenrecord", "--status"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 700; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 3000; running: root.open; repeat: true; onTriggered: root.refresh() }

    property FileView store: FileView {
        path: root.shell.home + "/.local/state/quickshell/screenrecord.json"
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.target = saved.target || "smart"
                root.desktopAudio = saved.desktopAudio === true
                root.micAudio = saved.micAudio === true
                root.webcam = saved.webcam === true
            } catch (error) { root.target = "smart" }
        }
    }

    component OptionRow: Item {
        required property string label
        property bool checked: false
        signal toggled
        width: recordColumn.width; height: 26
        Text {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: root.shell.alpha(root.shell.foreground, .8)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        ToggleSwitch {
            shell: root.shell
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            checked: parent.checked
            onToggled: parent.toggled()
        }
    }

    Column {
        id: recordColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "SCREEN RECORDING" }

        Text {
            visible: root.recording
            width: parent.width; text: "Recording in progress"
            color: root.shell.role("error", root.shell.foreground)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        Column {
            visible: !root.recording
            width: parent.width; spacing: 2
            Repeater {
                model: root.targets
                PopupRow {
                    required property var modelData
                    width: recordColumn.width; shell: root.shell
                    icon: modelData.icon
                    title: modelData.label
                    detail: modelData.detail
                    active: root.target === modelData.id
                    onClicked: { root.target = modelData.id; root.persist() }
                }
            }
        }

        PopupSeparator { visible: !root.recording; shell: root.shell }
        PopupSection { visible: !root.recording; shell: root.shell; text: "CAPTURE" }

        Column {
            visible: !root.recording
            width: parent.width; spacing: 0
            OptionRow {
                label: "Desktop audio"; checked: root.desktopAudio
                onToggled: { root.desktopAudio = !root.desktopAudio; root.persist() }
            }
            OptionRow {
                label: "Microphone"; checked: root.micAudio
                onToggled: { root.micAudio = !root.micAudio; root.persist() }
            }
            OptionRow {
                label: "Webcam overlay"; checked: root.webcam
                onToggled: { root.webcam = !root.webcam; root.persist() }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupRow {
            width: parent.width; shell: root.shell
            icon: root.recording ? "\u{f04db}" : "\u{f044a}"
            title: root.recording ? "Stop recording" : "Start recording"
            detail: root.recording ? String(root.report.tooltip || "") : "Saves to ~/Videos/Recordings"
            active: root.recording
            onClicked: root.recording ? root.stop() : root.start()
        }
    }
}

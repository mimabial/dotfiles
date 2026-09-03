import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "caffeine"
    contentWidth: Style.px(340)
    contentHeight: caffeineColumn.implicitHeight + padding * 2

    // the provider is the single source of truth; the popup only toggles
    property var report: ({})
    readonly property bool manual: report.manual === true
    readonly property bool audioEnabled: report.audioEnabled === true
    readonly property bool playing: report.playing === true
    readonly property bool audioHolding: audioEnabled && playing
    readonly property bool awake: manual || audioHolding
    readonly property string reason: String(report.reason || "None")

    function refresh() { if (!readProc.running) readProc.running = true }
    function toggle(script) { shell.run(["hyprshell", script]); settle.restart() }

    onOpenChanged: if (open) refresh()

    property Process readProc: Process {
        command: ["hyprshell", "quickshell/caffeine"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 400; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 3000; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Column {
        id: caffeineColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell; title: "Caffeine"
            status: root.awake ? "awake · " + root.reason : "idle allowed"
        }
        PopupSeparator { shell: root.shell }

        PopupRow {
            width: parent.width; shell: root.shell
            icon: root.manual ? "󰅶" : "󰛊"
            title: "Keep awake"
            detail: root.manual ? "Holding the session awake" : "Idle and lock run normally"
            active: root.manual
            onClicked: root.toggle("session/toggle-keep-awake.sh")
        }
        PopupRow {
            width: parent.width; shell: root.shell
            icon: root.audioHolding ? "󰎆" : "󰝚"
            title: "Stay awake while audio plays"
            detail: !root.audioEnabled ? "Disabled" : root.playing ? "Holding — audio is playing" : "Enabled · nothing playing"
            active: root.audioEnabled
            onClicked: root.toggle("session/toggle-audio-keep-awake.sh")
        }
    }
}

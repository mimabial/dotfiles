import QtQuick
import Quickshell.Services.Mpris

PopupCard {
    id: root
    popupName: "caffeine"
    contentWidth: Style.px(340)
    contentHeight: caffeineColumn.implicitHeight + padding * 2

    // the provider is the single source of truth; the popup only toggles
    readonly property bool manual: shell.keepAwakeManual
    readonly property bool audioEnabled: shell.keepAwakeAudio
    readonly property bool playing: Mpris.players.values.some(player => player.isPlaying)
    readonly property bool audioHolding: audioEnabled && playing
    readonly property bool fullscreenEnabled: shell.keepAwakeFullscreen
    readonly property bool fullscreenActive: shell.caffeineFullscreenActive
    readonly property bool gameActive: shell.caffeineGameActive
    readonly property bool windowHolding: fullscreenEnabled && (fullscreenActive || gameActive)
    readonly property bool awake: manual || audioHolding || windowHolding
    readonly property string reason: [[manual, "Manual"], [audioHolding, "Audio"], [fullscreenEnabled && fullscreenActive, "Fullscreen"], [fullscreenEnabled && gameActive, "Game"]].filter(([active]) => active).map(([, label]) => label).join(", ") || "None"
    function toggle(script) { shell.run([shell.home + "/.local/lib/hypr/" + script]) }

    Column {
        id: caffeineColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell; title: "Caffeine"
            status: root.awake ? "awake · " + root.reason : "idle allowed"
        }
        PopupSeparator { shell: root.shell }

        Column {
            width: parent.width; spacing: Style.xxs
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
            PopupRow {
                width: parent.width; shell: root.shell
                icon: root.gameActive ? "󰊴" : root.windowHolding ? "󰊓" : "󰍹"
                title: "Stay awake for fullscreen apps and games"
                detail: !root.fullscreenEnabled ? "Disabled" : root.gameActive ? "Holding — game is active" : root.fullscreenActive ? "Holding — app is fullscreen" : "Enabled · standing by"
                active: root.fullscreenEnabled
                onClicked: root.toggle("session/toggle-fullscreen-keep-awake.sh")
            }
        }
    }
}

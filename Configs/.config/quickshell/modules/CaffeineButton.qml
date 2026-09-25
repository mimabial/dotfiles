import QtQuick
import Quickshell.Services.Mpris
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool activeOnly: false
    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property bool audioPlaying: {
        for (let i = 0; i < players.length; ++i)
            if (players[i] && players[i].isPlaying) return true
        return false
    }
    readonly property bool audioHolding: shell.keepAwakeAudio && audioPlaying
    readonly property bool fullscreenActive: shell.caffeineFullscreenActive
    readonly property bool gameActive: shell.caffeineGameActive
    readonly property bool windowHolding: shell.keepAwakeFullscreen && (fullscreenActive || gameActive)
    readonly property bool awake: shell.keepAwakeManual || audioHolding || windowHolding
    css: "caffeine"
    active: awake
    visible: !activeOnly || awake
    text: shell.keepAwakeManual ? "󰅶" : audioHolding ? "󰎆" : gameActive && windowHolding ? "󰊴" : windowHolding ? "󰊓" : "󰛊"
    onClicked: button => button === Qt.RightButton
        ? shell.run(["hyprshell", "session/toggle-keep-awake.sh"])
        : shell.togglePopup("caffeine")

    CaffeinePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

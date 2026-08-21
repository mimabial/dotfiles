import QtQuick

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var player: Media.player
    visible: player !== null
    css: "custom-mediaplayer"
    textColor: shell.alpha(shell.role("act_fg", shell.foreground), .7)
    text: player ? Media.icon(player) + "  " + Media.remaining(player) : ""
    onClicked: button => button === Qt.RightButton ? player.togglePlaying()
        : button === Qt.MiddleButton ? player.next() : shell.togglePopup("media")
    onWheeled: delta => { if (player) delta > 0 ? player.previous() : player.next() }

    MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

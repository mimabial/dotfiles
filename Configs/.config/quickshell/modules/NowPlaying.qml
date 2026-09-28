pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.Ui as Ui
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var player: Media.player
    readonly property bool seekable: !!player?.canSeek && player.lengthSupported && player.length > 0
    css: "nowplaying"
    text: Media.icon(player)
    onClicked: shell.togglePopup("nowplaying")
    component Control: Ui.Button { fontFamily: root.shell.iconGlyphFont; fontSize: Style.title + 4; foreground: root.shell.foreground }
    PopupCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "nowplaying"
        contentWidth: Style.px(300); contentHeight: card.implicitHeight + padding * 2; keyboardHint: ""
        Column {
            id: card
            width: parent.width; spacing: Style.md
            Row {
                width: parent.width; spacing: Style.lg
                ClippingRectangle {
                    id: artwork
                    width: Style.px(56); height: width; radius: Style.sm; visible: art.status === Image.Ready
                    Image { id: art; anchors.fill: parent; source: Media.artUrl; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(width * 2, height * 2) }
                }
                Column {
                    width: parent.width - (artwork.visible ? artwork.width + parent.spacing : 0); anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: Media.title; elide: Text.ElideRight; font.bold: true; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
                    Text { width: parent.width; text: Media.artist; elide: Text.ElideRight; color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
                }
            }
            PopupSlider {
                width: parent.width; shell: root.shell; visible: root.seekable
                label: Media.time(Media.elapsed); valueText: Media.time(root.player?.length ?? 0)
                maximum: root.player?.length ?? 1; value: Media.elapsed
                onReleased: value => root.player.position = value
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.xl
                Control { text: "󰒮"; onClicked: Media.previous() }
                Control { text: root.player?.isPlaying ? "󰏤" : "󰐊"; onClicked: Media.playPause() }
                Control { text: "󰒭"; onClicked: Media.next() }
            }
        }
    }
}

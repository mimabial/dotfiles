pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var sink: Pipewire.defaultAudioSink
    css: "controlcenter"; text: "󰔡"
    onClicked: shell.togglePopup("controlcenter")
    component Tile: Item {
        id: tile
        required property string icon
        required property string title
        required property bool active
        signal clicked()
        Layout.fillWidth: true; implicitHeight: Style.px(40)
        Rectangle {
            id: badge
            width: Style.px(30); height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
            color: tile.active ? root.shell.accent : root.shell.alpha(root.shell.foreground, .12)
            Text { anchors.centerIn: parent; text: tile.icon; color: tile.active ? root.shell.background : root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body }
        }
        Column {
            anchors.left: badge.right; anchors.leftMargin: Style.md; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; text: tile.title; elide: Text.ElideRight; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true }
            Text { text: tile.active ? "On" : "Off"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    }
    PwObjectTracker { objects: [root.sink].filter(Boolean) }
    PopupCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "controlcenter"
        contentWidth: Style.px(320); contentHeight: panel.implicitHeight + padding * 2; keyboardHint: ""
        Column {
            id: panel
            width: parent.width; spacing: Style.md
            GridLayout {
                width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                Tile { icon: "󰖩"; title: "Wi-Fi"; active: Networking.wifiEnabled; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                Tile { icon: "󰂯"; title: "Bluetooth"; active: !!Bluetooth.defaultAdapter?.enabled; onClicked: root.shell.run(["hyprshell", "bluetooth/power", "toggle"]) }
                Tile { icon: "󱩌"; title: "Night Shift"; active: root.shell.sunsetEnabled === "1"; onClicked: root.shell.run(["hyprshell", "hyprsunset", "-t", "-q"]) }
                Tile { icon: "󰅶"; title: "Keep Awake"; active: root.shell.keepAwakeManual; onClicked: root.shell.run(["hyprshell", "session/toggle-keep-awake.sh"]) }
            }
            PopupSlider {
                width: parent.width; shell: root.shell; label: "Display"; visible: Backlight.device !== ""
                minimum: .05; value: Backlight.percent / 100
                onReleased: value => root.shell.run(["brightnessctl", "set", Math.round(value * 100) + "%"], Backlight.refresh)
            }
            PopupSlider {
                width: parent.width; shell: root.shell; label: "Sound"
                maximum: root.shell.volumeLimit; value: root.sink?.audio?.volume ?? 0
                onChanged: value => { if (root.sink?.audio) root.sink.audio.volume = value }
            }
            PopupRow {
                width: parent.width; shell: root.shell; visible: Media.hasMedia
                icon: Media.player?.isPlaying ? "󰏤" : "󰐊"; title: Media.title; detail: Media.artist
                onClicked: Media.playPause()
            }
        }
    }
}

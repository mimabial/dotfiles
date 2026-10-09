pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import ".."
import "StatusSymbols.js" as StatusSymbols

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool statusIcons: false
    readonly property real badgeSize: Style.px(30)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var wifi: Array.from(Networking.devices.values).find(device => device.type === DeviceType.Wifi)
    readonly property var wifiNetwork: Array.from(wifi?.networks.values ?? []).find(network => network.connected) ?? null
    readonly property string wifiName: wifiNetwork?.name ?? ""
    readonly property string bluetoothNames: Bluetooth.devices.values.filter(device => device.connected).map(device => device.name).join(", ")
    readonly property var indicators: [
        { nodes: Privacy.camera, color: shell.role("success", "#30d158"), icon: "󰄀", label: "Camera" },
        { nodes: Privacy.microphone, color: shell.role("warning", "#ff9f0a"), icon: "󰍬", label: "Microphone" },
        { nodes: Privacy.screen, color: shell.role("c5", "#bf5af2"), icon: "󰹑", label: "Screen Recording" }
    ].filter(indicator => indicator.nodes.length > 0)
    readonly property bool privacyShown: indicators.length > 0 || Privacy.location
    readonly property bool shown: text !== "" || statusIcons
    css: "controlcenter"; text: statusIcons ? "" : "󰔡"; symbol: statusIcons ? "" : "org.gnome.Tweaks"; symbolContext: "apps"
    onClicked: shell.togglePopup("controlcenter")
    trailingWidth: statusCluster.width + (privacyShown ? dots.width + Style.xs : 0)
    component StatusIcon: SymbolicIcon {
        anchors.verticalCenter: parent.verticalCenter
        color: root.textColor; size: root.symbolSize; directory: root.box.symbols ?? ""
    }
    Loader {
        id: statusCluster
        active: root.statusIcons
        anchors.right: dots.left; anchors.rightMargin: root.privacyShown ? Style.xs : 0; anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Row {
            spacing: Style.sm
            StatusIcon { name: StatusSymbols.wifi(Networking.wifiEnabled, root.wifiNetwork) }
            StatusIcon { name: StatusSymbols.volume(root.sink, !!root.sink?.audio?.muted) }
            StatusIcon { visible: UPower.displayDevice.isPresent; name: StatusSymbols.battery(UPower.displayDevice, UPower.onBattery) }
        }
    }
    Row {
        id: dots
        anchors.right: parent.right; anchors.rightMargin: root.box.margin[1] + root.box.padding[1]; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.xxs
        SymbolicIcon { visible: Privacy.location; anchors.verticalCenter: parent.verticalCenter; name: "location-services-active"; color: root.shell.foreground; size: Style.px(9) }
        Repeater {
            model: root.indicators
            Rectangle { required property var modelData; anchors.verticalCenter: parent.verticalCenter; width: Style.px(6); height: width; radius: width / 2; color: modelData.color }
        }
    }
    component Tile: Item {
        id: tile
        required property string icon
        required property string title
        required property bool active
        property string status: ""
        signal clicked()
        Layout.fillWidth: true; implicitHeight: Style.px(40)
        Rectangle {
            id: badge
            width: root.badgeSize; height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
            color: tile.active ? root.shell.accent : root.shell.alpha(root.shell.foreground, .12)
            Text { anchors.centerIn: parent; text: tile.icon; color: tile.active ? root.shell.background : root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body }
        }
        Column {
            anchors.left: badge.right; anchors.leftMargin: Style.md; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            Text { width: parent.width; text: tile.title; elide: Text.ElideRight; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true }
            Text { width: parent.width; text: tile.status || (tile.active ? "On" : "Off"); elide: Text.ElideRight; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    }
    PwObjectTracker { objects: [root.sink].filter(Boolean) }
    PopupCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "controlcenter"
        contentWidth: Style.px(320); contentHeight: panel.implicitHeight + padding * 2; keyboardHint: ""
        onOpenChanged: if (open) root.shell.refreshMenuState()
        Column {
            id: panel
            width: parent.width; spacing: Style.md
            Repeater {
                model: root.indicators
                PopupRow {
                    required property var modelData
                    width: parent.width; shell: root.shell; interactive: false; icon: modelData.icon; iconColor: modelData.color
                    title: modelData.nodes.map(node => Privacy.appName(node)).join(", "); detail: modelData.label + " in use"
                }
            }
            PopupRow { width: parent.width; shell: root.shell; interactive: false; visible: Privacy.location; icon: ""; iconColor: root.shell.role("info", root.shell.accent); title: "Location Services"; detail: "In use" }
            GridLayout {
                width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                Tile { icon: "󰖩"; title: "Wi-Fi"; status: root.wifiName; active: Networking.wifiEnabled; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                Tile { icon: "󰂯"; title: "Bluetooth"; status: root.bluetoothNames; active: !!Bluetooth.defaultAdapter?.enabled; onClicked: root.shell.run(["hyprshell", "bluetooth/power", "toggle"]) }
                Tile { icon: "󰂛"; title: "Focus"; active: root.shell.notificationsPaused; onClicked: root.shell.run(["hyprshell", "notify/notifications", "--toggle"], () => root.shell.refreshMenuState()) }
                Tile { icon: "󰍺"; title: "Mirroring"; active: Mirroring.active; onClicked: Mirroring.toggle() }
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
                width: parent.width; shell: root.shell; visible: Media.hasMedia; interactive: false
                iconSource: Media.artUrl; iconSize: root.badgeSize; title: Media.title; detail: Media.artist; rightInset: mediaControls.width + Style.sm
                Row {
                    id: mediaControls
                    anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                    TransportButton { shell: root.shell; text: "󰒮"; enabled: !!Media.player?.canGoPrevious; onClicked: Media.previous() }
                    TransportButton { shell: root.shell; text: Media.player?.isPlaying ? "󰏤" : "󰐊"; onClicked: Media.playPause() }
                    TransportButton { shell: root.shell; text: "󰒭"; enabled: Media.canNext(); onClicked: Media.next() }
                }
            }
        }
    }
}

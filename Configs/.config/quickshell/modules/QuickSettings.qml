pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import ".."
import "StatusSymbols.js" as StatusSymbols

// Windows 11 Quick Settings: the network, volume and battery icons share one
// button, and its flyout holds the toggle tiles, sliders and battery readout
BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property bool shown: true
    readonly property string symbols: box.symbols ?? ""
    readonly property int iconSize: Math.round(iconBoxPx)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var battery: UPower.displayDevice
    readonly property var network: {
        for (const device of Networking.devices.values)
            if (device.type === DeviceType.Wifi)
                for (const candidate of device.networks.values)
                    if (candidate.connected) return candidate
        return null
    }
    readonly property string networkSymbol: Networking.devices.values.some(device => device.type === DeviceType.Wired && device.connected) ? "network-wired"
        : network ? "network-wireless-signal-" + StatusSymbols.level(network.signalStrength, ["none", "weak", "ok", "good", "excellent"])
        : Networking.wifiEnabled ? "network-wireless-offline" : "network-wireless-disabled"
    readonly property string volumeSymbol: !sink?.audio || sink.audio.muted || sink.audio.volume === 0 ? "audio-volume-muted"
        : "audio-volume-" + StatusSymbols.level(sink.audio.volume / shell.volumeLimit, ["low", "medium", "high"])
    readonly property string batterySymbol: StatusSymbols.battery(battery, UPower.onBattery)
    readonly property string bluetoothNames: Bluetooth.devices.values.filter(device => device.connected).map(device => device.name).join(", ")
    css: "quicksettings"
    trailingWidth: icons.width
    onClicked: shell.togglePopup(popupOpen ? shell.popupName : "quicksettings")
    onWheeled: delta => { if (sink) shell.run(["hyprshell", "volume-control.sh", "-o", delta > 0 ? "i" : "d"]) }
    Row {
        id: icons
        anchors.right: parent.right; anchors.rightMargin: root.box.margin[1] + root.box.padding[1]; anchors.verticalCenter: parent.verticalCenter
        spacing: root.box.spacing || 0
        Repeater {
            model: [root.networkSymbol, root.volumeSymbol].concat(root.battery.isPresent ? [root.batterySymbol] : [])
            SymbolicIcon { required property string modelData; name: modelData; directory: root.symbols; color: root.textColor; size: root.iconSize }
        }
    }
    PwObjectTracker { objects: [root.sink].filter(Boolean) }

    component Details: Text {
        id: details
        required property string popup
        text: "\ueab6"; color: root.shell.foreground
        font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.shell.togglePopup(details.popup) }
    }
    component Tile: ColumnLayout {
        id: tile
        required property string symbol
        required property string title
        required property bool active
        property string details: ""
        signal toggled()
        Layout.fillWidth: true; Layout.preferredWidth: 1
        spacing: Style.sm
        Rectangle {
            Layout.fillWidth: true; implicitHeight: width / 2
            radius: root.box.borderRadius ?? root.shell.rounding
            color: tile.active ? root.shell.accent : root.shell.alpha(root.shell.foreground, toggleHover.hovered ? .12 : .06)
            border.width: tile.active ? 0 : 1; border.color: root.shell.alpha(root.shell.foreground, .1)
            RowLayout {
                anchors.fill: parent; spacing: 0
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    SymbolicIcon { anchors.centerIn: parent; name: tile.symbol; directory: root.symbols; size: root.iconSize; color: tile.active ? root.shell.background : root.shell.foreground }
                    HoverHandler { id: toggleHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: tile.toggled() }
                }
                Rectangle { visible: tile.details !== ""; Layout.fillHeight: true; Layout.margins: Style.lg; implicitWidth: 1; color: root.shell.alpha(tile.active ? root.shell.background : root.shell.foreground, .25) }
                Details { visible: tile.details !== ""; popup: tile.details; Layout.fillHeight: true; Layout.preferredWidth: Style.controlHeight; color: tile.active ? root.shell.background : root.shell.foreground }
            }
        }
        Text {
            Layout.fillWidth: true; text: tile.title; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    PopupCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "quicksettings"
        contentWidth: Style.px(360); contentHeight: panel.implicitHeight + padding * 2; keyboardHint: ""
        onOpenChanged: if (open) root.shell.refreshMenuState()
        ColumnLayout {
            id: panel
            width: parent.width; spacing: Style.sectionGap
            PopupRow {
                Layout.fillWidth: true; shell: root.shell; visible: Media.hasMedia; interactive: false
                iconSource: Media.artUrl; iconSize: Style.controlHeight; title: Media.title; detail: Media.artist; rightInset: mediaControls.width + Style.sm
                Row {
                    id: mediaControls
                    anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                    TransportButton { shell: root.shell; text: "󰒮"; enabled: !!Media.player?.canGoPrevious; onClicked: Media.previous() }
                    TransportButton { shell: root.shell; text: Media.player?.isPlaying ? "󰏤" : "󰐊"; onClicked: Media.playPause() }
                    TransportButton { shell: root.shell; text: "󰒭"; enabled: Media.canNext(); onClicked: Media.next() }
                }
            }
            GridLayout {
                Layout.fillWidth: true; columns: 3; columnSpacing: Style.lg; rowSpacing: Style.lg
                Tile { symbol: "network-wireless-signal-excellent"; title: root.network?.name ?? "Wi-Fi"; active: Networking.wifiEnabled; details: "network"; onToggled: Networking.wifiEnabled = !Networking.wifiEnabled }
                Tile { symbol: "bluetooth-active"; title: root.bluetoothNames || "Bluetooth"; active: !!Bluetooth.defaultAdapter?.enabled; details: "bluetooth"; onToggled: root.shell.run(["hyprshell", "bluetooth/power", "toggle"]) }
                Tile { symbol: "power-profile-power-saver"; title: "Energy saver"; active: PowerProfiles.profile === PowerProfile.PowerSaver; onToggled: root.shell.run(["hyprshell", "system/powerprofiles", "--set", active ? "balanced" : "power-saver"]) }
                Tile { symbol: "night-light"; title: "Night light"; active: root.shell.sunsetEnabled === "1"; onToggled: root.shell.run(["hyprshell", "hyprsunset", "-t", "-q"]) }
                Tile { symbol: "notifications-disabled"; title: "Do not disturb"; active: root.shell.notificationsPaused; onToggled: root.shell.run(["hyprshell", "notify/notifications", "--toggle"], () => root.shell.refreshMenuState()) }
                Tile { symbol: "screen-shared"; title: "Cast"; active: Mirroring.active; onToggled: Mirroring.toggle() }
            }
            RowLayout {
                Layout.fillWidth: true; visible: Backlight.device !== ""; spacing: Style.md
                SymbolicIcon { name: "display-brightness"; directory: root.symbols; size: root.iconSize; color: root.shell.foreground }
                PopupSlider {
                    Layout.fillWidth: true; shell: root.shell; valueText: ""; minimum: .05; value: Backlight.percent / 100
                    onReleased: value => root.shell.run(["brightnessctl", "set", Math.round(value * 100) + "%"], Backlight.refresh)
                }
                Item { implicitWidth: Style.controlHeight }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Style.md
                SymbolicIcon {
                    name: root.volumeSymbol; directory: root.symbols; size: root.iconSize; color: root.shell.foreground
                    TapHandler { onTapped: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted }
                }
                PopupSlider {
                    Layout.fillWidth: true; shell: root.shell; valueText: ""; maximum: root.shell.volumeLimit; value: root.sink?.audio?.volume ?? 0
                    onChanged: value => { if (root.sink?.audio) root.sink.audio.volume = value }
                }
                Details { popup: "audio"; Layout.preferredWidth: Style.controlHeight }
            }
            PopupSeparator { Layout.fillWidth: true; shell: root.shell }
            RowLayout {
                Layout.fillWidth: true
                Row {
                    visible: root.battery.isPresent; spacing: Style.md
                    SymbolicIcon { anchors.verticalCenter: parent.verticalCenter; name: root.batterySymbol; directory: root.symbols; size: root.iconSize; color: root.shell.foreground }
                    Text { text: Math.round(root.battery.percentage * 100) + "%"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.shell.togglePopup("power") }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "\ueb51"; color: root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { root.shell.closePopup(); root.shell.run(["hyprshell", "menutree"]) } }
                }
            }
        }
    }

    component Detail: LazyPopup { shell: root.shell; popupsAllowed: root.popupsAllowed }
    Detail { popup: "network"; owners: ["wifi", "wifi-menu"]; sourceComponent: Component { NetworkPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Detail { popup: "wifiqr"; owners: ["wifi", "wifi-menu"]; sourceComponent: Component { WifiQrPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Detail { popup: "bluetooth"; owners: ["bluetooth", "bluetooth-menu"]; sourceComponent: Component { BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Detail { popup: "audio"; owners: ["volume", "volume-slider", "sound-menu"]; sourceComponent: Component { AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Detail { popup: "power"; owners: ["battery", "powerprofile"]; sourceComponent: Component { PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
}

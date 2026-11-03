pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import ".."
import "StatusSymbols.js" as StatusSymbols

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var popupStyle: shell.style.box("quick-settings.popup")
    readonly property var actionStyle: shell.style.box("quick-settings.action")
    readonly property var tileStyle: shell.style.box("quick-settings.tile")
    readonly property var pagerStyle: shell.style.box("quick-settings.pager")
    readonly property int contentPadding: Style.px(popupStyle.contentPadding)
    readonly property string hyprLib: shell.home + "/.local/lib/hypr/"
    readonly property var devices: Array.from(Networking.devices.values)
    readonly property var wifi: devices.find(device => device.type === DeviceType.Wifi)
    readonly property var wired: devices.find(device => device.type === DeviceType.Wired && device.connected)
    readonly property var networks: Array.from(wifi?.networks.values ?? []).filter(network => network.name)
        .sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength)
    readonly property var network: networks.find(network => network.connected)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var paired: Bluetooth.devices.values.filter(device => device.paired || device.bonded || device.trusted)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var outputs: Pipewire.nodes.values.filter(node => node.audio && node.isSink && !node.isStream)
    readonly property bool airplaneMode: !Networking.wifiEnabled && !adapter?.enabled
    readonly property var pages: ({
        wifi: { title: "Wi-Fi", settings: "More Wi-Fi settings", popup: "network" },
        bluetooth: { title: "Bluetooth", settings: "More Bluetooth settings", popup: "bluetooth" },
        sound: { title: "Sound output", settings: "More sound settings", popup: "audio" }
    })
    property string actionError: ""
    property var actionNetwork: null
    property var requestedNetwork: null
    css: "quick-settings"; text: ""; trailingWidth: indicators.implicitWidth
    tooltip: "Quick settings"
    implicitHeight: indicators.implicitHeight + verticalInsets
    onClicked: shell.togglePopup("controlcenter")
    Accessible.role: Accessible.Button; Accessible.name: tooltip

    function runSetting(command) {
        if (settingAction.running) return
        actionError = ""
        settingAction.command = command
        settingAction.running = true
    }
    function setAirplaneMode(enabled) {
        Networking.wifiEnabled = !enabled
        if (adapter) runSetting([hyprLib + "bluetooth/power.sh", enabled ? "off" : "on"])
    }
    function activateNetwork(network) {
        actionError = ""
        actionNetwork = network
        if (network.connected) network.disconnect()
        else if (network.known || [WifiSecurityType.Open, WifiSecurityType.Owe].includes(network.security)) network.connect()
        else {
            requestedNetwork = network
            shell.togglePopup("network")
            networkSettings.activateRequested()
        }
    }
    Process {
        id: settingAction
        stderr: StdioCollector { id: settingError; waitForEnd: true }
        onExited: (code, status) => { if (code !== 0 || status !== 0) root.actionError = settingError.text.trim() || "The setting could not be changed." }
    }
    Connections {
        target: root.actionNetwork
        function onConnectionFailed(reason) { root.actionError = ConnectionFailReason.toString(reason) }
    }
    PwObjectTracker { objects: (panel.open ? root.outputs : []).concat([root.sink]).filter(Boolean) }
    Binding { target: root.wifi ?? null; property: "scannerEnabled"; value: true; when: !!root.wifi && panel.open && panel.page === "wifi" }

    component Icon: SymbolicIcon { color: root.contentColor; size: root.symbolSize; directory: root.box.symbols ?? "" }
    Row {
        id: indicators
        anchors.right: parent.right; anchors.rightMargin: root.box.margin[1] + root.box.padding[1]; anchors.verticalCenter: parent.verticalCenter
        spacing: root.box.spacing
        Icon { name: root.wired ? "network-wired" : StatusSymbols.wifi(Networking.wifiEnabled, root.network); context: root.wired ? "devices" : "status" }
        Icon { name: StatusSymbols.volume(root.sink, !!root.sink?.audio?.muted) }
        Icon { visible: UPower.displayDevice.isPresent; name: StatusSymbols.battery(UPower.displayDevice, UPower.onBattery) }
    }
    component Action: PopupIconButton {
        id: action
        required property string iconName
        property string iconContext: "actions"
        property real iconSize: Style.px(root.actionStyle.iconSize)
        shell: root.shell
        implicitWidth: Style.px(root.actionStyle.minWidth); implicitHeight: Style.px(root.actionStyle.minHeight)
        Accessible.role: Accessible.Button; Accessible.name: hint
        Accessible.onPressAction: action.clicked(Qt.LeftButton)
        SymbolicIcon {
            anchors.centerIn: parent; name: action.iconName; context: action.iconContext
            color: action.enabled ? action.glyphColor : root.shell.faintText; size: action.iconSize; directory: root.box.symbols ?? ""
        }
    }
    component Tile: Item {
        id: tile
        required property string title
        required property string iconName
        property bool checked: false
        property bool checkable: true
        property string submenu: ""
        readonly property bool navigable: enabled
        property bool cursored: false
        signal clicked()
        function activateKeyboard() { clicked() }
        function adjustKeyboard(direction) { if (submenu && direction > 0) { panel.page = submenu; return true } return false }
        Layout.fillWidth: true; Layout.fillHeight: true
        implicitHeight: face.height + Style.px(root.tileStyle.labelGap) + label.implicitHeight
        opacity: enabled ? 1 : Style.faintTextAlpha
        Accessible.role: Accessible.Button; Accessible.name: title
        Accessible.checkable: checkable; Accessible.checked: checked
        Accessible.onPressAction: tile.clicked()
        Rectangle {
            id: face
            width: parent.width; height: Style.px(root.tileStyle.minHeight); radius: root.shell.rounding
            color: tile.cursored ? root.shell.hoverFill() : tile.checked ? root.shell.selectedFill()
                : root.shell.alpha(root.shell.foreground, Style.fieldFillAlpha)
            SymbolicIcon {
                anchors.centerIn: parent; anchors.horizontalCenterOffset: -arrow.width / 2
                name: tile.iconName; color: root.shell.foreground; size: Style.px(root.tileStyle.iconSize); directory: root.box.symbols ?? ""
            }
            MouseArea {
                anchors.fill: parent; anchors.rightMargin: arrow.width; cursorShape: Qt.PointingHandCursor
                onClicked: tile.clicked()
            }
            Action {
                id: arrow
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: tile.submenu ? Style.px(root.tileStyle.splitWidth) : 0; height: parent.height; visible: tile.submenu !== ""
                iconName: "go-next"; hint: tile.title + " options"
                onClicked: panel.page = tile.submenu
                Rectangle { width: root.shell.borderWidth; height: parent.height; color: root.shell.alpha(root.shell.foreground, Style.fieldBorderAlpha) }
            }
        }
        Text {
            id: label
            anchors.top: face.bottom; anchors.topMargin: Style.px(root.tileStyle.labelGap); width: parent.width
            text: tile.title; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        PopupPointer { shell: root.shell; row: tile }
    }
    component Level: RowLayout {
        id: level
        required property string title
        required property string iconName
        property real value: 0
        property real maximum: 1
        property bool canMute: false
        signal muteRequested()
        signal changed(real value)
        signal released(real value)
        spacing: Style.controlGap
        Action { iconName: level.iconName; iconContext: "status"; hint: level.canMute ? "Mute or unmute" : level.title; enabled: level.canMute; onClicked: level.muteRequested() }
        PopupSlider {
            Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; shell: root.shell; valueText: ""
            appearance: root.shell.style.box("quick-settings.slider")
            value: level.value; maximum: level.maximum; Accessible.name: level.title
            onChanged: value => level.changed(value); onReleased: value => level.released(value)
        }
        Action { iconName: "go-next"; visible: level.canMute; hint: "Select a sound output"; onClicked: panel.page = "sound" }
    }
    PopupCard {
        id: panel
        property string page: ""
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "controlcenter"
        contentWidth: Style.px(root.popupStyle.width); padding: 0
        contentHeight: body.implicitHeight; keyboardHint: ""
        onPageChanged: { clearCursor(); Qt.callLater(rebuildRows) }
        onOpenChanged: if (open) root.shell.refreshMenuState()
            else { page = ""; tilePages.setCurrentIndex(0); root.actionError = ""; root.actionNetwork = null }
        function handleKey(event) {
            if ((event.key === Qt.Key_Escape || event.key === Qt.Key_Back) && page) { page = ""; return true }
            if (!page && (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)) {
                tilePages.setCurrentIndex(Math.max(0, Math.min(tilePages.count - 1, tilePages.currentIndex + (event.key === Qt.Key_PageDown ? 1 : -1))))
                return true
            }
            return defaultKey(event)
        }
        Column {
            id: body
            width: parent.width; spacing: 0
            Column {
                x: root.contentPadding; width: parent.width - x * 2; spacing: Style.px(root.popupStyle.sectionGap)
                topPadding: root.contentPadding; bottomPadding: root.contentPadding; visible: panel.page === ""
                PopupRow {
                    width: parent.width; shell: root.shell; visible: Media.hasMedia
                    iconSource: Media.artUrl; title: Media.title; detail: Media.artist; rightInset: transport.width + Style.sm
                    onClicked: root.shell.togglePopup("media")
                    Row {
                        id: transport
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        Action { iconName: "media-skip-backward"; hint: "Previous"; enabled: !!Media.player?.canGoPrevious; onClicked: Media.previous() }
                        Action { iconName: Media.player?.isPlaying ? "media-playback-pause" : "media-playback-start"; hint: Media.player?.isPlaying ? "Pause" : "Play"; onClicked: Media.playPause() }
                        Action { iconName: "media-skip-forward"; hint: "Next"; enabled: Media.canNext(); onClicked: Media.next() }
                    }
                }
                Item {
                    width: parent.width; implicitHeight: tilePages.height
                    SwipeView {
                        id: tilePages
                        width: parent.width; height: primaryActions.implicitHeight
                        orientation: Qt.Vertical; clip: true
                        onCurrentIndexChanged: { panel.clearCursor(); Qt.callLater(panel.rebuildRows) }
                        Binding { target: tilePages.contentItem; property: "highlightMoveDuration"; value: Style.hoverDuration }
                        WheelHandler {
                            target: null
                            onWheel: event => {
                                const delta = event.angleDelta.y || event.pixelDelta.y
                                if (delta) tilePages.setCurrentIndex(Math.max(0, Math.min(tilePages.count - 1, tilePages.currentIndex + (delta < 0 ? 1 : -1))))
                                event.accepted = true
                            }
                        }
                        GridLayout {
                            id: primaryActions
                            enabled: SwipeView.isCurrentItem
                            columns: 3; rowSpacing: Style.px(root.tileStyle.rowGap); columnSpacing: Style.px(root.tileStyle.columnGap)
                            uniformCellWidths: true; uniformCellHeights: true
                            Tile { title: "Wi-Fi"; iconName: StatusSymbols.wifi(Networking.wifiEnabled, root.network); checked: Networking.wifiEnabled; submenu: "wifi"; enabled: !!root.wifi; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                            Tile { title: "Bluetooth"; iconName: root.adapter?.enabled ? "bluetooth-active" : "bluetooth-disabled"; checked: !!root.adapter?.enabled; submenu: "bluetooth"; enabled: !!root.adapter && !settingAction.running; onClicked: root.runSetting([root.hyprLib + "bluetooth/power.sh", "toggle"]) }
                            Tile { title: "Airplane mode"; iconName: "airplane-mode"; checked: root.airplaneMode; enabled: (!!root.wifi || !!root.adapter) && !settingAction.running; onClicked: root.setAirplaneMode(!root.airplaneMode) }
                            Tile { title: "Energy saver"; iconName: "power-profile-power-saver"; checked: PowerProfiles.profile === PowerProfile.PowerSaver; enabled: !settingAction.running; onClicked: root.runSetting([root.hyprLib + "system/powerprofiles.sh", "--set", checked ? "balanced" : "power-saver"]) }
                            Tile { title: "Night light"; iconName: "night-light"; checked: root.shell.sunsetEnabled === "1"; enabled: !settingAction.running; onClicked: root.runSetting(["bash", root.hyprLib + "system/hyprsunset.sh", "-t", "-q"]) }
                            Tile { title: "Do not disturb"; iconName: "notifications-disabled"; checked: Notifications.report.paused === true; onClicked: root.shell.run([root.hyprLib + "notify/notifications.py", "--toggle"], Notifications.refresh) }
                        }
                        GridLayout {
                            enabled: SwipeView.isCurrentItem
                            columns: primaryActions.columns; rowSpacing: primaryActions.rowSpacing; columnSpacing: primaryActions.columnSpacing
                            uniformCellWidths: true; uniformCellHeights: true
                            Tile { title: "VPN"; iconName: "network-vpn"; checkable: false; onClicked: root.shell.togglePopup("vpn") }
                            Tile { title: "Display"; iconName: "devices/video-display"; checkable: false; onClicked: root.shell.togglePopup("monitor") }
                            Tile { title: "Volume mixer"; iconName: "audio-volume-high"; checkable: false; onClicked: root.shell.togglePopup("audio") }
                            Tile { title: "Microphone"; iconName: "devices/audio-input-microphone"; checkable: false; onClicked: root.shell.togglePopup("microphone") }
                            Tile { title: "Power mode"; iconName: "power-profile-balanced"; checkable: false; onClicked: root.shell.togglePopup("power") }
                            Tile { title: "Keep awake"; iconName: root.shell.keepAwakeManual ? "caffeine-cup-full" : "caffeine-cup-empty"; checked: root.shell.keepAwakeManual; onClicked: root.shell.run([root.hyprLib + "session/toggle-keep-awake.sh"]) }
                        }
                    }
                    Column {
                        anchors.left: tilePages.right; anchors.leftMargin: (root.contentPadding - width) / 2; anchors.verticalCenter: tilePages.verticalCenter
                        spacing: Style.px(root.pagerStyle.spacing)
                        Action { implicitWidth: Style.px(root.pagerStyle.width); implicitHeight: Style.px(root.pagerStyle.buttonHeight); iconSize: Style.px(root.pagerStyle.iconSize); visible: enabled; iconName: "go-up"; hint: "Previous quick actions"; enabled: tilePages.currentIndex > 0; onClicked: tilePages.decrementCurrentIndex() }
                        Repeater {
                            model: tilePages.count
                            Action {
                                iconName: ""; implicitWidth: Style.px(root.pagerStyle.width); implicitHeight: Style.px(root.pagerStyle.buttonHeight)
                                id: pageDot
                                required property int index
                                shell: root.shell; hint: "Quick actions page " + (index + 1) + " of " + tilePages.count
                                Accessible.role: Accessible.Button; Accessible.name: hint
                                Accessible.onPressAction: pageDot.clicked(Qt.LeftButton)
                                onClicked: tilePages.setCurrentIndex(index)
                                Rectangle {
                                    anchors.centerIn: parent; width: Style.px(pageDot.index === tilePages.currentIndex ? root.pagerStyle.activeDotSize : root.pagerStyle.dotSize); height: width; radius: width / 2
                                    color: pageDot.index === tilePages.currentIndex ? root.shell.accent : root.shell.faintText
                                }
                            }
                        }
                        Action { implicitWidth: Style.px(root.pagerStyle.width); implicitHeight: Style.px(root.pagerStyle.buttonHeight); iconSize: Style.px(root.pagerStyle.iconSize); visible: enabled; iconName: "go-down"; hint: "Next quick actions"; enabled: tilePages.currentIndex < tilePages.count - 1; onClicked: tilePages.incrementCurrentIndex() }
                    }
                }
                PopupSeparator { x: -root.contentPadding; width: panel.contentWidth; shell: root.shell }
                Column {
                    width: parent.width; spacing: Style.px(root.popupStyle.sliderGap)
                    Level {
                        width: parent.width; title: "Brightness"; iconName: "display-brightness"; visible: Backlight.device !== ""; value: Backlight.percent / 100
                        onReleased: value => root.shell.run(["brightnessctl", "--device", Backlight.device, "set", Math.round(value * 100) + "%"], Backlight.refresh)
                    }
                    Level {
                        width: parent.width; title: "Volume"; iconName: StatusSymbols.volume(root.sink, !!root.sink?.audio?.muted)
                        enabled: !!root.sink?.audio; canMute: true; value: root.sink?.audio?.volume ?? 0; maximum: root.shell.volumeLimit
                        onMuteRequested: root.sink.audio.muted = !root.sink.audio.muted
                        onChanged: value => { if (root.sink?.audio) root.sink.audio.volume = value }
                    }
                }
            }
            Column {
                x: root.contentPadding; width: parent.width - x * 2; spacing: Style.controlGap
                topPadding: root.contentPadding; bottomPadding: root.contentPadding; visible: panel.page !== ""
                PopupRow { width: parent.width; shell: root.shell; icon: "󰁍"; title: root.pages[panel.page]?.title ?? ""; onClicked: panel.page = "" }
                PopupSeparator { shell: root.shell }
                PopupToggleRow { width: parent.width; shell: root.shell; visible: panel.page === "wifi"; title: "Wi-Fi"; checked: Networking.wifiEnabled; onToggled: Networking.wifiEnabled = !Networking.wifiEnabled }
                PopupToggleRow { width: parent.width; shell: root.shell; visible: panel.page === "bluetooth"; title: "Bluetooth"; checked: !!root.adapter?.enabled; enabled: !!root.adapter && !settingAction.running; onToggled: root.runSetting([root.hyprLib + "bluetooth/power.sh", "toggle"]) }
                Repeater {
                    model: panel.page === "wifi" && Networking.wifiEnabled ? root.networks : []
                    PopupRow {
                        required property var modelData
                        width: parent.width; shell: root.shell; title: modelData.name; active: modelData.connected
                        detail: modelData.stateChanging ? "Connecting…" : modelData.connected ? "Connected" : ""
                        value: modelData.security === WifiSecurityType.Open ? "" : "󰌾"; enabled: !modelData.stateChanging
                        onClicked: root.activateNetwork(modelData)
                    }
                }
                Repeater {
                    model: panel.page === "bluetooth" && root.adapter?.enabled ? root.paired : []
                    PopupRow {
                        required property var modelData
                        width: parent.width; shell: root.shell; title: modelData.name; active: modelData.connected; enabled: !settingAction.running
                        detail: (modelData.connected ? "Connected" : "Paired") + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                        onClicked: root.runSetting([root.hyprLib + "bluetooth/device-action.sh", modelData.connected ? "disconnect" : "connect", String(modelData.address)])
                    }
                }
                Repeater {
                    model: panel.page === "sound" ? root.outputs : []
                    PopupRow {
                        required property var modelData
                        width: parent.width; shell: root.shell; title: modelData.description || modelData.nickname || modelData.name
                        active: modelData === root.sink; value: active ? "✓" : ""
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }
                PopupRow {
                    width: parent.width; shell: root.shell; interactive: false
                    visible: panel.page === "wifi" && (!Networking.wifiEnabled || !root.networks.length)
                        || panel.page === "bluetooth" && (!root.adapter?.enabled || !root.paired.length)
                        || panel.page === "sound" && !root.outputs.length
                    title: panel.page === "wifi" ? Networking.wifiEnabled ? "Searching for networks…" : "Wi-Fi is off"
                        : panel.page === "bluetooth" ? root.adapter?.enabled ? "No paired devices" : "Bluetooth is off" : "No sound outputs"
                }
                PopupRow { width: parent.width; shell: root.shell; title: root.pages[panel.page]?.settings ?? ""; onClicked: root.shell.togglePopup(root.pages[panel.page].popup) }
            }
            PopupHint {
                shell: root.shell; error: true
                width: parent.width; text: root.actionError
            }
            Rectangle {
                width: parent.width; height: Style.px(root.popupStyle.footerHeight)
                color: "transparent"
                PopupSeparator { shell: root.shell }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: root.contentPadding; anchors.rightMargin: root.contentPadding; spacing: Style.sm
                    Action { iconName: StatusSymbols.battery(UPower.displayDevice, UPower.onBattery); iconContext: "status"; hint: "Power settings"; onClicked: root.shell.togglePopup("power") }
                    Text {
                        text: UPower.displayDevice.isPresent ? Math.round(UPower.displayDevice.percentage * 100) + "%" : "Power"
                        color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.shell.togglePopup("power") }
                    }
                    Item { Layout.fillWidth: true }
                    Action { iconName: "preferences-system"; iconContext: "categories"; hint: "Settings"; onClicked: { root.shell.closePopup(); root.shell.run([root.hyprLib + "window/settings.sh"]) } }
                }
            }
        }
    }
    LazyPopup {
        id: networkSettings
        shell: root.shell; popup: "network"; owners: ["wifi"]; popupsAllowed: root.popupsAllowed
        function activateRequested() {
            const popup = item as NetworkPopup
            if (popup && root.requestedNetwork) { popup.activate(root.requestedNetwork); root.requestedNetwork = null }
        }
        onLoaded: activateRequested()
        sourceComponent: Component { NetworkPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    LazyPopup {
        shell: root.shell; popup: "bluetooth"; owners: ["bluetooth"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    LazyPopup {
        shell: root.shell; popup: "audio"; owners: ["volume"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    LazyPopup {
        shell: root.shell; popup: "microphone"; owners: ["microphone"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; microphoneMode: true } }
    }
    LazyPopup {
        shell: root.shell; popup: "vpn"; owners: ["vpn"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Loader {
        id: displaySettings
        asynchronous: true; visible: false
        Connections {
            target: root.shell
            function onPopupNameChanged() {
                if (root.popupsAllowed && root.shell.popupName === "monitor" && !root.shell.liveModules.includes("display") && !displaySettings.source.toString())
                    displaySettings.setSource(Qt.resolvedUrl("../monitor/DisplayPanel.qml"), {anchorItem: root, shell: root.shell, popupName: "monitor"})
            }
        }
    }
    LazyPopup {
        shell: root.shell; popup: "power"; owners: ["powerprofile"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    LazyPopup {
        shell: root.shell; popup: "wifiqr"; owners: ["wifi"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { WifiQrPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    LazyPopup {
        shell: root.shell; popup: "media"; owners: ["mediaplayer", "nowplaying"]; popupsAllowed: root.popupsAllowed
        sourceComponent: Component { MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
}

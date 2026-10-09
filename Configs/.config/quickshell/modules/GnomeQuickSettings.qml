pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.Ui
import "StatusSymbols.js" as StatusSymbols
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property string hyprLib: shell.home + "/.local/lib/hypr/"
    readonly property var devices: Array.from(Networking.devices.values)
    readonly property var wifi: devices.find(device => device.type === DeviceType.Wifi)
    readonly property var wired: devices.find(device => device.type === DeviceType.Wired)
    readonly property var network: Array.from(wifi?.networks.values ?? []).find(network => network.connected)
    readonly property var networks: Array.from(wifi?.networks.values ?? []).filter(network => network.name).sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength)
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var paired: Bluetooth.devices.values.filter(device => device.paired || device.bonded || device.trusted)
    readonly property var connectedBluetooth: Bluetooth.devices.values.filter(device => device.connected)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var audioDevices: Pipewire.nodes.values.filter(node => node.audio && !node.isStream)
    readonly property var profiles: [{ title: "Power Saver", value: "power-saver", profile: PowerProfile.PowerSaver }, { title: "Balanced", value: "balanced", profile: PowerProfile.Balanced }].concat(PowerProfiles.hasPerformanceProfile ? [{ title: "Performance", value: "performance", profile: PowerProfile.Performance }] : [])
    readonly property var activeProfile: profiles.find(profile => profile.profile === PowerProfiles.profile)
    readonly property bool balanced: PowerProfiles.profile === PowerProfile.Balanced
    readonly property string profileIcon: "power-profile-" + (activeProfile?.value ?? "balanced")
    property string lastUnbalancedProfile: "power-saver"
    onActiveProfileChanged: if (activeProfile && !balanced) lastUnbalancedProfile = activeProfile.value
    readonly property bool darkStyle: shell.colorMode === "dark" || shell.colorMode === "auto" && shell.hyprVar("COLOR_SCHEME", "prefer-dark") === "prefer-dark"
    readonly property bool airplaneMode: !Networking.wifiEnabled && !adapter?.enabled
    readonly property bool nightLight: shell.sunsetEnabled === "1"
    readonly property bool doNotDisturb: Notifications.report.paused === true
    readonly property var backgroundApps: SystemTray.items.values
    property var appMenuItem: null
    readonly property var vpn: GnomeStatus.vpn
    readonly property string keyboardDevice: GnomeStatus.keyboardDevice
    readonly property int keyboardBrightness: GnomeStatus.keyboardBrightness
    readonly property int keyboardMaximum: GnomeStatus.keyboardMaximum
    readonly property int tileColumns: 2
    readonly property var sessionActions: [
        { title: "Suspend", command: ["hyprshell", "session/suspend.sh"] },
        { title: "Restart…", confirmText: "Restart", question: "Restart now?", command: ["hyprshell", "system/powerctl.sh", "reboot"] },
        { title: "Power Off…", confirmText: "Power Off", question: "Power off now?", command: ["hyprshell", "system/powerctl.sh", "shutdown"] },
        { title: "Log Out…", confirmText: "Log Out", question: "Log out of this session?", command: ["hyprshell", "logout"], separated: true }
    ]
    property var pendingSessionAction: null
    readonly property var submenus: ({
        wifi: { title: "Wi-Fi", icon: StatusSymbols.wifi(Networking.wifiEnabled, network), checked: Networking.wifiEnabled, settings: "All Networks", popup: "network" },
        bluetooth: { title: "Bluetooth", icon: "bluetooth-active", checked: !!adapter?.enabled, settings: "Bluetooth Settings", popup: "bluetooth" },
        power: { title: "Power Mode", icon: profileIcon, checked: !balanced, settings: "Power Settings", popup: "power" },
        sound: { title: "Sound Output", icon: "audio-headphones", context: "devices", settings: "Sound Settings", popup: "audio" },
        microphone: { title: "Sound Input", icon: "audio-input-microphone", context: "devices", settings: "Sound Settings", popup: "microphone" },
        session: { title: "Power Off", icon: "system-shutdown", context: "actions" },
        background: { title: "Background Apps", icon: "application-x-executable", context: "mimetypes" }
    })
    readonly property var openSubmenu: submenus[panel.expanded] ?? null
    Component.onCompleted: ++GnomeStatus.readers
    Component.onDestruction: --GnomeStatus.readers
    css: "controlcenter"; text: ""; trailingWidth: indicators.implicitWidth
    onClicked: shell.togglePopup("controlcenter")
    function setProfile(value) { shell.run([hyprLib + "system/powerprofiles.sh", "--set", value]) }
    function setAirplaneMode(enabled) {
        shell.run(["nmcli", "radio", "all", enabled ? "off" : "on"])
        if (adapter) adapter.enabled = !enabled
    }
    function setKeyboardBacklight(value) { shell.run(["brightnessctl", "--device", keyboardDevice, "set", String(value)], GnomeStatus.refreshKeyboard) }
    function openOptions(name, opener) {
        if (!(name in submenus)) return shell.togglePopup(name)
        if (panel.expanded === name) { panel.expanded = ""; return }
        panel.submenuY = opener.mapToItem(content, 0, opener.height).y + Style.sm
        panel.expanded = name
    }
    function runSessionAction(action) { shell.closePopup(); shell.run(action.command) }
    function chooseSessionAction(action) {
        if (action.question) pendingSessionAction = action
        else runSessionAction(action)
    }
    function openAppMenu(item) { appMenuItem = item; shell.togglePopup("tray") }
    function activateBackgroundApp(item) {
        if (item.onlyMenu) return openAppMenu(item)
        shell.closePopup()
        item.activate()
    }
    component Icon: SymbolicIcon {
        size: root.symbolSize; color: root.contentColor; directory: root.box.symbols ?? ""
    }
    Row {
        id: indicators
        anchors.right: parent.right; anchors.rightMargin: root.box.margin[1] + root.box.padding[1]; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.sm
        Icon { visible: Privacy.screen.length > 0; name: "screen-shared"; color: root.shell.role("warning", root.shell.foreground) }
        Icon { visible: Privacy.camera.length > 0; name: "camera-web"; context: "devices"; color: root.shell.role("warning", root.shell.foreground) }
        Icon { visible: Privacy.microphone.length > 0; name: "microphone-sensitivity-high"; color: root.shell.role("warning", root.shell.foreground) }
        Icon { visible: Privacy.location; name: "location-services-active" }
        Icon { visible: root.nightLight; name: "night-light" }
        Icon { visible: root.vpn.state === "connected"; name: "network-vpn" }
        Icon { visible: !!root.wired?.connected || !root.airplaneMode && !!root.wifi; name: root.wired?.connected ? "network-wired" : StatusSymbols.wifi(Networking.wifiEnabled, root.network); context: root.wired?.connected ? "devices" : "status" }
        Icon { visible: root.doNotDisturb; name: "notifications-disabled" }
        Icon { visible: root.connectedBluetooth.length > 0; name: "bluetooth-active" }
        Icon { visible: root.airplaneMode && (!!root.wifi || !!root.adapter); name: "airplane-mode" }
        Icon { name: StatusSymbols.volume(root.sink, !!root.sink?.audio?.muted) }
        Icon { visible: !root.balanced; name: root.profileIcon }
        Icon { visible: UPower.displayDevice.isPresent; name: StatusSymbols.battery(UPower.displayDevice, UPower.onBattery) }
    }
    component Action: PopupIconButton {
        id: action
        required property string iconName
        property string iconContext: "actions"
        shell: root.shell
        SymbolicIcon { anchors.centerIn: parent; name: action.iconName; context: action.iconContext; color: action.glyphColor; size: Style.body; directory: root.box.symbols ?? "" }
    }
    component Level: RowLayout {
        id: level
        required property string title
        required property string iconName
        property real value: 0
        property real maximum: 1
        property bool canMute: false
        property bool available: true
        property bool muted: false
        property string submenu: ""
        signal muteRequested()
        signal changed(real value)
        signal released(real value)
        spacing: Style.sm
        Action { iconName: level.iconName; iconContext: "status"; enabled: level.canMute; hint: level.canMute ? level.muted ? "Unmute " + level.title : "Mute " + level.title : level.title; onClicked: level.muteRequested() }
        PopupSlider { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; shell: root.shell; valueText: ""; enabled: level.available; value: level.value; maximum: level.maximum; Accessible.name: level.title; onChanged: value => level.changed(value); onReleased: value => level.released(value) }
        Action { iconName: "go-next"; visible: level.submenu !== ""; hint: level.title + " options"; onClicked: root.openOptions(level.submenu, level) }
    }
    component Tile: Rectangle {
        id: tile
        required property string title
        required property string iconName
        property string iconContext: "status"
        property string detail: ""
        property bool checked: false
        property string submenu: ""
        readonly property bool navigable: enabled
        property bool cursored: false
        signal clicked()
        function activateKeyboard() { clicked() }
        function adjustKeyboard(direction) { if (submenu && direction > 0) { root.openOptions(submenu, tile); return true } return false }
        Layout.fillWidth: true; Layout.fillHeight: true
        implicitHeight: Math.max(Style.controlHeight, labels.implicitHeight + Style.controlPaddingY * 2)
        radius: root.shell.rounding
        readonly property bool highlighted: cursored || tileHover.hovered
        readonly property color textColor: root.shell.role(cursored || tileHover.hovered ? "hvr_fg" : checked ? "act_fg" : "alt_fg", root.shell.foreground)
        color: highlighted ? root.shell.hoverFill() : checked ? root.shell.selectedFill() : root.shell.alpha(root.shell.role("alt_bg", root.shell.background), Style.selectedFillAlpha)
        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        border.width: root.shell.borderWidth
        border.color: highlighted ? root.shell.hoverEdge() : checked ? root.shell.selectedEdge() : "transparent"
        Accessible.role: Accessible.Button; Accessible.name: title; Accessible.checkable: true; Accessible.checked: checked
        SymbolicIcon { id: icon; anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter; name: tile.iconName; context: tile.iconContext; color: tile.textColor; size: Style.title; directory: root.box.symbols ?? "" }
        Column {
            id: labels
            anchors.left: icon.right; anchors.leftMargin: Style.controlGap; anchors.right: arrow.left; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
            spacing: Style.xxs
            Text { width: parent.width; text: tile.title; color: tile.textColor; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: tile.checked; elide: Text.ElideRight }
            Text { visible: tile.detail !== ""; width: parent.width; text: tile.detail; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
        }
        MouseArea { anchors.fill: parent; anchors.rightMargin: arrow.width; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
        Action {
            id: arrow
            anchors.right: parent.right; anchors.rightMargin: tile.submenu ? Style.sm : 0; anchors.verticalCenter: parent.verticalCenter
            width: tile.submenu ? implicitWidth : 0; visible: tile.submenu !== ""
            iconName: "go-next"; glyphColor: tile.textColor; hint: tile.title + " options"
            onClicked: root.openOptions(tile.submenu, tile)
        }
        PopupPointer { shell: root.shell; row: tile }
    }
    PwObjectTracker { objects: (panel.open ? root.audioDevices : []).concat([root.sink, root.source]).filter(Boolean) }
    Binding { target: root.wifi ?? null; property: "scannerEnabled"; value: true; when: !!root.wifi && panel.open && panel.expanded === "wifi" }
    PopupCard {
        id: panel
        property string expanded: ""
        property real submenuY: 0
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "controlcenter"
        contentWidth: Style.px(400); keyboardHint: ""
        contentHeight: Math.max(content.implicitHeight, submenuCard.visible ? submenuCard.y + submenuCard.height : 0) + padding * 2
        onOpenChanged: if (open) { root.shell.refreshMenuState(); GnomeStatus.refresh(); GnomeStatus.refreshKeyboard() } else { expanded = ""; root.pendingSessionAction = null }
        function handleKey(event) {
            if (sessionConfirm.opened) return sessionConfirm.handleKey(event)
            if (event.key === Qt.Key_Escape && expanded) { expanded = ""; return true }
            return defaultKey(event)
        }
        Column {
            id: content
            width: parent.width; spacing: Style.sectionGap
            enabled: panel.expanded === ""
            opacity: enabled ? 1 : Style.faintTextAlpha
            RowLayout {
                width: parent.width; spacing: Style.sm
                Action { visible: UPower.displayDevice.isPresent; iconName: StatusSymbols.battery(UPower.displayDevice, UPower.onBattery); iconContext: "status"; hint: "Battery and Power"; onClicked: root.shell.togglePopup("power") }
                Text { visible: UPower.displayDevice.isPresent; text: Math.round(UPower.displayDevice.percentage * 100) + "%"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
                Item { Layout.fillWidth: true }
                Action { iconName: "camera-photo"; iconContext: "devices"; hint: "Take Screenshot"; onClicked: root.shell.togglePopup("screenshot") }
                Action { iconName: "preferences-system"; iconContext: "categories"; hint: "Settings"; onClicked: { root.shell.closePopup(); root.shell.run([root.hyprLib + "window/settings.sh"]) } }
                Action { iconName: "system-lock-screen"; iconContext: "status"; hint: "Lock Screen"; onClicked: { root.shell.closePopup(); root.shell.run([root.hyprLib + "session/lock-screen.sh"]) } }
                Action { id: sessionButton; iconName: "system-shutdown"; hint: "Power Off Menu"; onClicked: root.openOptions("session", sessionButton) }
            }
            Repeater {
                model: [ { nodes: Privacy.camera, title: "Camera in use" }, { nodes: Privacy.microphone, title: "Microphone in use" }, { nodes: Privacy.screen, title: "Screen sharing" } ].filter(entry => entry.nodes.length)
                PopupRow { required property var modelData; width: parent.width; shell: root.shell; interactive: false; title: modelData.title; detail: modelData.nodes.map(node => Privacy.appName(node)).join(", ") }
            }
            Column {
                width: parent.width; spacing: Style.sm
                Level { width: parent.width; title: "Sound"; iconName: StatusSymbols.volume(root.sink, muted); canMute: !!root.sink?.audio; muted: !!root.sink?.audio?.muted; value: root.sink?.audio?.volume ?? 0; maximum: root.shell.volumeLimit; submenu: "sound"; onMuteRequested: root.sink.audio.muted = !root.sink.audio.muted; onChanged: value => { if (root.sink?.audio) root.sink.audio.volume = value }; available: !!root.sink?.audio }
                Level { width: parent.width; title: "Microphone"; iconName: muted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high"; visible: Privacy.microphone.length > 0; canMute: !!root.source?.audio; muted: !!root.source?.audio?.muted; value: root.source?.audio?.volume ?? 0; available: !!root.source?.audio; submenu: "microphone"; onMuteRequested: root.source.audio.muted = !root.source.audio.muted; onChanged: value => { if (root.source?.audio) root.source.audio.volume = value } }
                Level { width: parent.width; title: "Brightness"; iconName: "display-brightness"; visible: Backlight.device !== ""; value: Backlight.percent / 100; onReleased: value => root.shell.run(["brightnessctl", "--device", Backlight.device, "set", Math.round(value * 100) + "%"], Backlight.refresh) }
            }
            GridLayout {
                width: parent.width; columns: root.tileColumns; rowSpacing: Style.controlGap; columnSpacing: Style.controlGap; uniformCellHeights: true; uniformCellWidths: true
                Tile { visible: !!root.wired; title: "Wired"; detail: root.wired?.connected ? "Connected" : "Disconnected"; iconName: "network-wired"; iconContext: "devices"; checked: !!root.wired?.connected; submenu: "network"; onClicked: root.wired.connected ? root.wired.disconnect() : root.shell.run(["nmcli", "device", "connect", root.wired.name]) }
                Tile { visible: !!root.wifi; title: "Wi-Fi"; detail: root.network?.name || ""; iconName: StatusSymbols.wifi(Networking.wifiEnabled, root.network); checked: Networking.wifiEnabled; submenu: "wifi"; onClicked: Networking.wifiEnabled = !Networking.wifiEnabled }
                Tile { visible: root.vpn.provider !== "none"; title: "VPN"; detail: root.vpn.relay || ""; iconName: "network-vpn"; checked: root.vpn.state === "connected"; submenu: "vpn"; onClicked: root.shell.run([root.hyprLib + "quickshell/vpn-toggle.sh"], GnomeStatus.refresh) }
                Tile { visible: !!root.adapter; title: "Bluetooth"; detail: root.connectedBluetooth.length === 1 ? root.connectedBluetooth[0].name : root.connectedBluetooth.length ? root.connectedBluetooth.length + " Connected" : ""; iconName: "bluetooth-active"; checked: !!root.adapter?.enabled; submenu: "bluetooth"; onClicked: root.adapter.enabled = !root.adapter.enabled }
                Tile { title: "Power Mode"; detail: root.activeProfile?.title ?? ""; iconName: root.profileIcon; checked: !root.balanced; submenu: "power"; onClicked: root.setProfile(root.balanced ? root.lastUnbalancedProfile : "balanced") }
                Tile { title: "Night Light"; iconName: "night-light"; checked: root.nightLight; onClicked: root.shell.run(["bash", root.hyprLib + "system/hyprsunset.sh", "-t", "-q"]) }
                Tile { title: "Dark Style"; iconName: "weather-clear-night"; checked: root.darkStyle; onClicked: root.shell.run([root.hyprLib + "theme/color-mode.sh", "--set", root.shell.colorSource, root.darkStyle ? "light" : "dark"]) }
                Tile { title: "Do Not Disturb"; iconName: "notifications-disabled"; checked: root.doNotDisturb; onClicked: root.shell.run([root.hyprLib + "notify/notifications.py", "--toggle"], Notifications.refresh) }
                Tile { visible: root.keyboardDevice !== ""; title: "Keyboard Backlight"; iconName: "keyboard-brightness"; checked: root.keyboardBrightness > 0; onClicked: root.setKeyboardBacklight(root.keyboardBrightness > 0 ? 0 : root.keyboardMaximum) }
                Tile { visible: !!root.wifi || !!root.adapter; title: "Airplane Mode"; iconName: "airplane-mode"; checked: root.airplaneMode; onClicked: root.setAirplaneMode(!root.airplaneMode) }
                Tile {
                    id: backgroundAppsTile
                    visible: root.backgroundApps.length > 0; Layout.columnSpan: root.tileColumns
                    title: root.backgroundApps.length === 1 ? "1 Background App" : root.backgroundApps.length + " Background Apps"
                    iconName: "application-x-executable"; iconContext: "mimetypes"; submenu: "background"
                    onClicked: root.openOptions("background", backgroundAppsTile)
                }
            }
        }
        MouseArea { anchors.fill: content; enabled: panel.expanded !== ""; onClicked: panel.expanded = "" }
        Rectangle {
            id: submenuCard
            visible: root.openSubmenu !== null
            y: panel.submenuY; width: content.width; height: submenuItems.implicitHeight + Style.controlPaddingY * 2
            radius: root.shell.rounding
            color: root.shell.background
            border.width: root.shell.borderWidth; border.color: root.shell.selectedEdge()
            Column {
                id: submenuItems
                x: Style.controlPaddingX; y: Style.controlPaddingY; width: parent.width - x * 2; spacing: Style.sm
                RowLayout {
                    width: parent.width; spacing: Style.controlGap
                    Rectangle {
                        implicitWidth: Style.controlHeight; implicitHeight: implicitWidth; radius: width / 2
                        color: root.openSubmenu?.checked ? root.shell.selectedFill() : root.shell.alpha(root.shell.role("alt_bg", root.shell.background), Style.selectedFillAlpha)
                        SymbolicIcon { anchors.centerIn: parent; name: root.openSubmenu?.icon ?? ""; context: root.openSubmenu?.context ?? "status"; color: root.shell.foreground; size: Style.title; directory: root.box.symbols ?? "" }
                    }
                    Text { Layout.fillWidth: true; text: root.openSubmenu?.title ?? ""; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true; elide: Text.ElideRight }
                }
                Repeater {
                    model: panel.expanded === "wifi" && Networking.wifiEnabled ? root.networks : []
                    PopupRow { required property var modelData; width: parent.width; shell: root.shell; title: modelData.name; active: modelData.connected; value: modelData.connected ? "✓" : ""; onClicked: modelData.connected ? modelData.disconnect() : modelData.known || modelData.security === WifiSecurityType.Open ? modelData.connect() : root.shell.togglePopup("network") }
                }
                Repeater {
                    model: panel.expanded === "bluetooth" && root.adapter?.enabled ? root.paired : []
                    PopupRow { required property var modelData; width: parent.width; shell: root.shell; title: modelData.name; active: modelData.connected; detail: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""; onClicked: root.shell.run([root.hyprLib + "bluetooth/device-action.sh", modelData.connected ? "disconnect" : "connect", String(modelData.address)]) }
                }
                Repeater {
                    model: panel.expanded === "power" ? root.profiles : []
                    PopupRow { required property var modelData; width: parent.width; shell: root.shell; title: modelData.title; active: PowerProfiles.profile === modelData.profile; onClicked: root.setProfile(modelData.value) }
                }
                Repeater {
                    model: panel.expanded === "sound" ? root.audioDevices.filter(node => node.isSink) : []
                    PopupRow { required property var modelData; width: parent.width; shell: root.shell; title: modelData.description || modelData.nickname || modelData.name; active: modelData === root.sink; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
                }
                Repeater {
                    model: panel.expanded === "microphone" ? root.audioDevices.filter(node => !node.isSink) : []
                    PopupRow { required property var modelData; width: parent.width; shell: root.shell; title: modelData.description || modelData.nickname || modelData.name; active: modelData === root.source; onClicked: Pipewire.preferredDefaultAudioSource = modelData }
                }
                Repeater {
                    model: panel.expanded === "session" ? root.sessionActions : []
                    Column {
                        id: sessionEntry
                        required property var modelData
                        width: parent.width; spacing: Style.sm
                        PopupSeparator { shell: root.shell; visible: !!sessionEntry.modelData.separated }
                        PopupRow { width: parent.width; shell: root.shell; title: sessionEntry.modelData.title; onClicked: root.chooseSessionAction(sessionEntry.modelData) }
                    }
                }
                Repeater {
                    model: panel.expanded === "background" ? root.backgroundApps : []
                    PopupRow {
                        required property var modelData
                        width: parent.width; shell: root.shell
                        iconSource: modelData.icon; title: modelData.title || modelData.id
                        value: modelData.hasMenu ? "\u{f01d9}" : ""; valueClickable: modelData.hasMenu
                        onClicked: root.activateBackgroundApp(modelData)
                        onValueClicked: root.openAppMenu(modelData)
                    }
                }
                PopupSeparator { shell: root.shell; visible: !!root.openSubmenu?.settings }
                PopupRow { width: parent.width; shell: root.shell; visible: !!root.openSubmenu?.settings; title: root.openSubmenu?.settings ?? ""; onClicked: root.shell.togglePopup(root.openSubmenu.popup) }
            }
        }
        ConfirmDialog {
            id: sessionConfirm
            anchors.fill: parent; opened: root.pendingSessionAction !== null
            message: root.pendingSessionAction?.question ?? ""
            confirmText: root.pendingSessionAction?.confirmText ?? ""
            background: root.shell.background; foreground: root.shell.foreground; selectedText: root.shell.role("error", root.shell.foreground); fontFamily: root.shell.fontFamily; cornerRadius: root.shell.rounding
            onCanceled: root.pendingSessionAction = null
            onConfirmed: { const action = root.pendingSessionAction; root.pendingSessionAction = null; root.runSessionAction(action) }
        }
    }
    component Host: LazyPopup { shell: root.shell; popupsAllowed: root.popupsAllowed; owners: [] }
    Host { popup: "tray"; owners: ["tray"]; sourceComponent: Component { TrayMenu { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; handle: root.appMenuItem?.menu ?? null; label: root.appMenuItem ? root.appMenuItem.title || root.appMenuItem.id : "" } } }
    Host { popup: "network"; owners: ["wifi", "wifi-menu"]; sourceComponent: Component { NetworkPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "bluetooth"; owners: ["bluetooth", "bluetooth-menu"]; sourceComponent: Component { BluetoothPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "audio"; owners: ["volume", "sound-menu"]; sourceComponent: Component { AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "microphone"; owners: ["microphone"]; sourceComponent: Component { AudioPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; microphoneMode: true } } }
    Host { popup: "power"; owners: ["powerprofile", "battery"]; sourceComponent: Component { PowerPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "powermenu"; owners: ["powerbutton"]; sourceComponent: Component { PowerMenuPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "screenshot"; owners: ["screenshot"]; sourceComponent: Component { ScreenshotPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "desktop"; owners: ["windowlayout"]; sourceComponent: Component { DesktopPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "vpn"; owners: ["vpn", "vpn-menu"]; sourceComponent: Component { VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "hyprsunset"; owners: ["hyprsunset"]; sourceComponent: Component { HyprsunsetPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { popup: "caffeine"; owners: ["caffeine"]; sourceComponent: Component { CaffeinePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Host { id: monitorHost; popup: "monitor"; owners: ["display", "display-menu"]; asynchronous: true; onActiveChanged: if (active && String(source) === "") setSource(Qt.resolvedUrl("../monitor/DisplayPanel.qml"), { anchorItem: root, shell: root.shell }) }
}

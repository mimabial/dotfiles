import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import "modules"

PanelWindow {
    id: root
    required property var shell
    property bool sidebar: shell.layoutName === "sidebar"
    property bool onLeft: shell.layoutName === "left" || shell.layoutName === "sidebar"
    property bool active: shell.mode === "main" && !shell.userHidden
    // one bar exists per screen, and each popup installs its own focus grab;
    // if two bars open a popup at once the grabs cancel each other, so only
    // the bar on the focused monitor owns them
    readonly property bool popupsAllowed: active && (!Hyprland.focusedMonitor
        || !screen || Hyprland.focusedMonitor.name === screen.name)
    anchors.top: true
    anchors.bottom: true
    anchors.left: onLeft
    anchors.right: !onLeft
    margins.left: onLeft ? (active ? 0 : -implicitWidth) : 0
    margins.right: onLeft ? 0 : (active ? 0 : -implicitWidth)
    // composition is data: reordering the bar is editing layouts/<name>.json
    readonly property var registry: ({"menu": mod_menu, "taskbar": mod_taskbar, "tray": mod_tray, "updates": mod_updates, "gpu": mod_gpu, "cpu": mod_cpu, "memory": mod_memory, "disk": mod_disk, "fan": mod_fan, "minmax": mod_minmax, "dmark": mod_dmark, "wifi": mod_wifi, "speed": mod_speed, "bluetooth": mod_bluetooth, "vpn": mod_vpn, "printers": mod_printers, "disks": mod_disks, "connectivity": mod_connectivity, "desktop": mod_desktop, "barlayout": mod_barlayout, "colormode": mod_colormode, "datetime": mod_datetime, "date": mod_date, "eyecare": mod_eyecare, "forecast": mod_forecast, "info": mod_info, "info-drawer": mod_info_drawer, "mark": mod_mark, "mediaplayer": mod_mediaplayer, "notification": mod_notification, "dunst": mod_dunst, "power": mod_power, "privacybutton": mod_privacybutton, "screen": mod_screen, "screenshot": mod_screenshot, "screenrecord": mod_screenrecord, "terminal": mod_terminal, "status": mod_status, "submap": mod_submap, "tui-drawer": mod_tui_drawer, "workspaces": mod_workspaces})
    readonly property var layout: shell.barLayout
    readonly property var section: shell.style.box(".modules-left")
    implicitWidth: mainColumn.implicitWidth + section.margin[1] + section.margin[3]
    color: shell.barColor
    exclusionMode: active ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-bar"
    WlrLayershell.layer: WlrLayer.Top
    readonly property bool popupOpen: shell.popupName !== "" && popupsAllowed
    property bool exclusivePhase: false
    WlrLayershell.keyboardFocus: popupOpen && exclusivePhase
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.OnDemand
    onPopupOpenChanged: {
        if (!popupOpen) return
        exclusivePhase = true
        shell.focusPriming = true
        focusPrime.restart()
        focusSettle.restart()
    }
    Timer { id: focusPrime; interval: 150; onTriggered: root.exclusivePhase = false }
    // the grab settles a little after the mode drops back
    Timer { id: focusSettle; interval: 450; onTriggered: root.shell.focusPriming = false }

    Component { id: mod_menu; StartButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_taskbar; WindowList { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_tray; Tray { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_notification; NotificationModule { shell: root.shell; popupsAllowed: root.popupsAllowed; reverse: root.shell.layoutName === "main"; Layout.fillWidth: true } }
    Component { id: mod_dunst; DunstModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screen; ScreenModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screenshot; ScreenshotModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screenrecord; ScreenRecordModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_terminal; TerminalModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_desktop; DesktopModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_barlayout; BarLayoutModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_colormode; ColorModeModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_eyecare; EyecareModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_status; Status { shell: root.shell; reverse: true; showNetwork: false; showPower: false; showLogout: false; popupsEnabled: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_privacybutton; PrivacyButton { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_mediaplayer; MediaplayerModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_datetime; DatetimeModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_date; BarButton { id: dateButton; shell: root.shell; css: "clock.date"; fontWeight: Font.Bold; text: Qt.formatDate(root.shell.clock.date, root.shell.store.mainDateNumeric ? "dd|\nMM|\nyy " : "ddd\ndd\nMMM"); onClicked: button => button === Qt.RightButton ? root.shell.store.mainDateNumeric = !root.shell.store.mainDateNumeric : root.shell.togglePopup("clock"); Layout.fillWidth: true; ClockPopup { anchorItem: dateButton; shell: dateButton.shell; popupEnabled: root.popupsAllowed } } }
    Component { id: mod_tui_drawer; TuiDrawerModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; vertical: true; activeOnly: true; popupEnabled: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_submap; ScriptButton { shell: root.shell; css: "custom-submap"; command: ["hyprshell", "keybinds/submap-status"]; interval: 86400000; fontWeight: Font.Bold; Layout.fillWidth: true } }
    Component { id: mod_forecast; ForecastModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_mark; MarkModule { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_info; InfoModule { shell: root.shell; popupsAllowed: root.popupsAllowed; single: root.shell.layoutName === "main"; Layout.fillWidth: true } }
    Component { id: mod_info_drawer; InfoDrawerModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_updates; UpdatesModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_gpu; GpuModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_cpu; CpuModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_memory; MemoryModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_disk; DiskModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_fan; FanModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_minmax; MinmaxModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_dmark; DmarkModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_wifi; WifiModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_bluetooth; BluetoothModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_speed; SpeedModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_vpn; VpnModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_printers; PrintersModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_disks; DisksModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_connectivity; ConnectivityModule { shell: root.shell; popupsAllowed: root.popupsAllowed; pairDrawers: root.shell.layoutName === "main"; Layout.fillWidth: true } }
    Component { id: mod_power; PowerModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.leftMargin: root.section.margin[3]; anchors.rightMargin: root.section.margin[1]
        anchors.topMargin: root.section.margin[0]; anchors.bottomMargin: root.section.margin[2]
        spacing: 0

        Repeater {
            model: root.layout
            delegate: Loader {
                required property var modelData
                readonly property string moduleId: typeof modelData === "string" ? modelData : String(modelData.id || "")
                readonly property var moduleProps: typeof modelData === "string" ? null : (modelData.props || null)
                Layout.fillWidth: moduleId !== "date"
                Layout.alignment: moduleId === "date" ? Qt.AlignHCenter : 0
                Layout.fillHeight: moduleId === "spacer"
                visible: moduleId === "spacer" || !item ? true
                    : item.shown !== undefined ? item.shown
                    : item.text !== undefined ? String(item.text) !== ""
                    : true
                sourceComponent: moduleId === "spacer" ? null : root.registry[moduleId] || null
                onLoaded: {
                    if (!moduleProps || !item) return
                    for (const key in moduleProps) item[key] = moduleProps[key]
                }
            }
        }
    }
}

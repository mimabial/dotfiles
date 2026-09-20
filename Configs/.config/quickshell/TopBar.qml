import QtQuick
import QtQuick.Layouts
import "modules"

BarSurface {
    id: root
    readonly property var section: shell.style.box(".modules-left")
    readonly property var layout: shell.barLayout
    readonly property bool onTop: shell.barEdge === "top"
    readonly property var registry: ({"menu": mod_menu, "taskbar": mod_taskbar, "mediaplayer": mod_mediaplayer, "cpu": mod_cpu, "gpu": mod_gpu, "memory": mod_memory, "disk": mod_disk, "disks": mod_disks, "fan": mod_fan, "datetime": mod_datetime, "indicators": mod_indicators, "language": mod_language, "updates": mod_updates, "converter": mod_converter, "sudoku": mod_sudoku, "workspaces": mod_workspaces, "weather": mod_weather, "submap": mod_submap, "audio": mod_audio, "bluetooth": mod_bluetooth, "vpn": mod_vpn, "wifi": mod_wifi, "speed": mod_speed, "volume": mod_volume, "display": mod_display, "powerprofile": mod_powerprofile, "powerbutton": mod_powerbutton, "monitor": mod_monitor, "capture": mod_capture, "notification-group": mod_notification_group, "notification": mod_notification, "github": mod_github, "tasks": mod_tasks, "privacy": mod_privacy, "tray": mod_tray, "connectivity": mod_connectivity, "appearance": mod_appearance, "power": mod_power})
    readonly property var centerModules: layout.center || []
    readonly property int centerAnchorIndex: moduleIndex(centerModules, String(layout.centerAnchor || ""))
    readonly property var centerBeforeModules: centerAnchorIndex < 0 ? [] : centerModules.slice(0, centerAnchorIndex)
    readonly property var centerAnchorModules: centerAnchorIndex < 0 ? [] : [centerModules[centerAnchorIndex]]
    readonly property var centerAfterModules: centerAnchorIndex < 0 ? [] : centerModules.slice(centerAnchorIndex + 1)
    function moduleIndex(modules, id) {
        for (let i = 0; i < modules.length; i++) {
            const entry = modules[i]
            if ((typeof entry === "string" ? entry : String(entry.id || "")) === id) return i
        }
        return -1
    }
    active: shell.mode === "horizontal" && !shell.userHidden
    anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
    margins.left: floatMargin("left"); margins.right: floatMargin("right")
    margins.top: onTop ? (active ? floatMargin("top") : -implicitHeight) : floatMargin("top")
    margins.bottom: onTop ? floatMargin("bottom") : (active ? floatMargin("bottom") : -implicitHeight)
    implicitHeight: Math.max(leftRow.implicitHeight, centerFallback.implicitHeight, centerBefore.implicitHeight, centerAnchor.implicitHeight, centerAfter.implicitHeight, rightRow.implicitHeight)
    Component { id: mod_menu; StartButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_taskbar; WindowList { shell: root.shell; allWorkspaces: true; framed: true; Layout.fillHeight: true } }
    Component { id: mod_mediaplayer; MediaButton { shell: root.shell; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }
    Component { id: mod_cpu; CpuReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_gpu; GpuReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_memory; MemoryReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_disk; DiskReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_disks; DisksGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_fan; FanReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_datetime; ClockButton { shell: root.shell; kind: "top"; css: "clock.time-alt"; Layout.fillHeight: true; textColor: root.shell.accent; popupEnabled: root.popupsAllowed } }
    Component { id: mod_indicators; IndicatorsGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_language; LanguageButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_updates; UpdatesButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_converter; ConverterButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_sudoku; SudokuButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; activeOnly: true; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_weather; BarButton { id: weatherButton; shell: root.shell; css: "weather"; text: Weather.output.text; Layout.fillHeight: true; onClicked: root.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Component { id: mod_submap; SubmapButton { shell: root.shell; alt: true; Layout.fillHeight: true; baseColor: root.shell.alpha(root.shell.role("br", root.shell.foreground), .7) } }
    Component { id: mod_audio; AudioGroup { shell: root.shell; vertical: false; Layout.fillHeight: true; popupsAllowed: root.popupsAllowed } }
    Component { id: mod_bluetooth; BluetoothGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_vpn; VpnButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_wifi; WifiGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_speed; SpeedButton { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_volume; AudioButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_display; DisplayButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_powerprofile; PowerProfileButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_powerbutton; LogoutButton { shell: root.shell; text: "󱨦"; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_monitor; BarGroup {
        shell: root.shell; vertical: false; reverse: true; Layout.fillHeight: true
        primary: Component { DisplayButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
        secondary: Component { ScriptButton { shell: root.shell; css: "hyprsunset"; Layout.fillHeight: true; radius: root.shell.moduleRadius; command: ["hyprshell", "hyprsunset", "-rq"]; interval: 86400000; refreshKey: root.shell.sunsetEnabled; onClicked: root.shell.run(["hyprshell", "hyprsunset", "-t"]) } }
    } }
    Component { id: mod_capture; BarGroup {
        shell: root.shell; css: "capture-group"; vertical: false; reverse: true; Layout.fillHeight: true; radius: root.shell.moduleRadius
        slots: [topRecordSlot, topPickerSlot, topShotSlot]
        Component { id: topRecordSlot; ScriptButton { id: topRecord; shell: root.shell; css: "screenrecord"; Layout.fillHeight: true; textColor: root.shell.role(output.class === "recording" ? "error" : "c1", root.shell.foreground); command: ["hyprshell", "screenrecord", "--status"]; indicator: "screenrecord"; polling: output.class === "recording"; interval: 3000; Component.onCompleted: topRecord.refresh(); onClicked: button => root.shell.run(["hyprshell", "screenrecord", button === Qt.RightButton ? "--quit" : "--toggle"]) } }
        Component { id: topPickerSlot; ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "colorpicker"; command: ["hyprshell", "color-picker.sh", "-j"]; interval: 86400000; onClicked: root.shell.run(["hyprshell", "color-picker.sh"]); onWheeled: delta => root.shell.run(["hyprshell", "color-picker.sh", delta > 0 ? "-u" : "-d"]) } }
        Component { id: topShotSlot; BarButton { Layout.fillHeight: true; shell: root.shell; css: "screenshot"; text: "󰄄"; tooltip: "<b>Screenshot</b>\nLeft: Select area\nMiddle: Full screen\nRight: Focused monitor"; onClicked: button => root.shell.run(["hyprshell", "screenshot", button === Qt.MiddleButton ? "p" : button === Qt.RightButton ? "m" : "smart"]) } }
    } }
    Component { id: mod_notification_group; NotificationGroup {
        shell: root.shell; popupsAllowed: root.popupsAllowed
        vertical: false; reverse: true; Layout.fillHeight: true
    } }
    Component { id: mod_notification; NotificationButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_github; GithubButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_tasks; TasksButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_privacy; PrivacyButton { shell: root.shell; Layout.fillHeight: true } }
    Component { id: mod_tray; Tray { shell: root.shell; framed: true; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_connectivity; ConnectivityGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; Layout.fillHeight: true } }
    Component { id: mod_appearance; AppearanceGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: false; reverse: true; Layout.fillHeight: true } }
    Component { id: mod_power; PowerGroup {
        shell: root.shell; popupsAllowed: root.popupsAllowed
        vertical: false; reverse: false; Layout.fillHeight: true
    } }

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.leftMargin: root.section.margin[3] + root.section.padding[3]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.left || []
    }
    BarSection {
        id: centerFallback
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAnchorIndex < 0 ? root.centerModules : []
    }
    BarSection {
        id: centerBefore
        anchors.right: centerAnchor.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerBeforeModules
    }
    BarSection {
        id: centerAnchor
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAnchorModules
    }
    BarSection {
        id: centerAfter
        anchors.left: centerAnchor.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAfterModules
    }
    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.rightMargin: root.section.margin[1] + root.section.padding[1]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.right || []
    }

    PopupHost { shell: root.shell; anchorItem: leftRow; popupsAllowed: root.popupsAllowed }
}

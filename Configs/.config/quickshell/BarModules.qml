pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "modules"
import qs.systemstats

Item {
    id: catalog
    required property var shell
    required property bool popupsAllowed
    required property real taskbarAvailableWidth
    readonly property bool winbar: shell.mode === "winbar"
    readonly property bool horizontal: shell.mode === "horizontal"
    readonly property real appIconSize: winbar ? shell.style.box("taskbar").iconSize ?? 0 : 0
    readonly property real controlIconSize: appIconSize ? appIconSize - shell.style.box("taskbar").spacing : 0
    readonly property real controlButtonStep: {
        if (!controlIconSize) return 0
        const box = shell.style.box("#taskbar button")
        return controlIconSize + box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3]
            + 2 * Math.max(box.borderWidth, box.borderBottomWidth || 0) + shell.style.box("taskbar").spacing
    }
    readonly property var registry: ({
        "menu": mod_menu, "taskbar": mod_taskbar, "workspaces": mod_workspaces, "submap": mod_submap,
        "tray": mod_tray,
        "mediaplayer": mod_media, "datetime": mod_datetime,
        "weather": catalog.winbar ? mod_winbar_weather : mod_weather,
        "systemstats": mod_systemstats, "agents": mod_agents,
        "wifi": mod_wifi, "bluetooth": mod_bluetooth, "vpn": mod_vpn,
        "printers": mod_printers, "removable": mod_removable, "volume": mod_volume, "microphone": mod_microphone,
        "volume-slider": mod_volume_slider, "microphone-slider": mod_microphone_slider, "backlight-slider": mod_backlight_slider,
        "display": mod_display, "updates": mod_updates, "notifications": mod_notifications, "tasks": mod_tasks,
        "wallpaper": mod_wallpaper, "colormode": mod_colormode, "barlayout": mod_barlayout, "windowlayout": mod_windowlayout, "workflows": mod_workflows,
        "colorpicker": mod_colorpicker, "powerprofile": mod_powerprofile, "powerbutton": mod_powerbutton,
        "bitwarden": mod_bitwarden, "github": mod_github, "privacy": mod_privacy, "language": mod_language,
        "hyprsunset": mod_hyprsunset, "caffeine": mod_caffeine, "screenrecord": mod_screenrecord,
        "screenshot": mod_screenshot, "webcam": mod_webcam, "terminal": mod_terminal,
        "converter": mod_converter, "sudoku": mod_sudoku, "games": mod_games,
        "appmenu": mod_appmenu, "battery": mod_battery, "spotlight": mod_spotlight, "controlcenter": mod_controlcenter, "nowplaying": mod_nowplaying, "sound-menu": mod_sound,
        "wifi-menu": mod_wifi_menu, "bluetooth-menu": mod_bluetooth_menu, "vpn-menu": mod_vpn_menu, "language-menu": mod_language_menu, "mirroring-menu": mod_mirroring_menu, "display-menu": mod_display_menu,
        "notification-center": mod_notification_center,
        "task-view": mod_task_view, "launcher-strip": mod_launcher_strip
    })

    Component { id: mod_menu; StartButton { shell: catalog.shell; iconSize: catalog.appIconSize; fixedWidth: iconSize ? iconSize + horizontalInsets : 0; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_taskbar; WindowList { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; availableWidth: catalog.taskbarAvailableWidth; Layout.fillHeight: true } }
    Component { id: mod_workspaces; Workspaces { shell: catalog.shell; activeOnly: !catalog.winbar; hideActive: catalog.winbar; popupEnabled: !catalog.winbar && catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_submap; SubmapButton { shell: catalog.shell; alt: true; baseColor: catalog.shell.alpha(catalog.shell.role("br", catalog.shell.foreground), .7); Layout.fillHeight: true } }
    Component { id: mod_tray; Tray { shell: catalog.shell; registry: catalog.registry; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_media; MediaButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_datetime; ClockButton { shell: catalog.shell; kind: catalog.shell.clockKind; css: "datetime"; textColor: catalog.shell.clockKind === "top" ? catalog.shell.accent : catalog.shell.foreground; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_weather; WeatherStats { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_systemstats; SystemStats { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_agents; AgentsButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_wifi; WifiButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_bluetooth; BluetoothButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_vpn; VpnButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_printers; PrintersButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_removable; RemovableButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_volume; AudioButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_microphone; MicrophoneButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_display; DisplayButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_volume_slider; AudioButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; levelIcons: false; Layout.fillHeight: true
        VolumeSlider { shell: catalog.shell; z: 2; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter } } }
    Component { id: mod_microphone_slider; MicrophoneButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true
        VolumeSlider { shell: catalog.shell; microphone: true; z: 2; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter } } }
    Component { id: mod_backlight_slider; DisplayButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true
        BrightnessSlider { shell: catalog.shell; z: 2; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter } } }
    Component { id: mod_updates; UpdatesButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_notifications; NotificationButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; indicator: "dnd"; polling: false; showBadge: false; Layout.fillHeight: true; Component.onCompleted: refresh() } }
    Component { id: mod_tasks; TasksButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_wallpaper; WallpaperButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_colormode; ScriptButton {
        id: colorButton; shell: catalog.shell; css: "colormode"; tooltip: ""; Layout.fillHeight: true
        command: ["hyprshell", "quickshell/color-mode"]; polling: false; refreshKey: catalog.shell.palette
        Component.onCompleted: refresh()
        onClicked: button => button === Qt.LeftButton
            ? catalog.shell.togglePopup("colormode")
            : catalog.shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
        ColorModePopup { anchorItem: colorButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed }
    } }
    Component { id: mod_barlayout; BarButton {
        id: barButton; shell: catalog.shell; css: "barlayout-button"; text: catalog.shell.barLayoutIcon(); Layout.fillHeight: true
        onClicked: button => button === Qt.LeftButton ? catalog.shell.togglePopup("barlayout")
            : catalog.shell.run(["hyprshell", "quickshell/layout", button === Qt.RightButton ? "previous" : "next"])
        BarLayoutPopup { anchorItem: barButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed }
    } }
    Component { id: mod_windowlayout; WindowLayoutButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_workflows; ScriptButton {
        shell: catalog.shell; css: "workflows"; opensPopup: true; Layout.fillHeight: true
        command: ["hyprshell", "util/workflows", "--bar"]; polling: false; refreshKey: catalog.shell.workflow
        Component.onCompleted: refresh()
        onClicked: catalog.shell.togglePopup("desktop")
    } }
    Component { id: mod_colorpicker; ColorPickerButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_powerprofile; PowerProfileButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_powerbutton; LogoutButton { shell: catalog.shell; text: ""; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_bitwarden; BitwardenButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_github; GithubButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_privacy; PrivacyButton { shell: catalog.shell; Layout.fillHeight: true } }
    Component { id: mod_language; LanguageButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_hyprsunset; HyprsunsetButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_caffeine; CaffeineButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_screenrecord; ScreenRecordButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_screenshot; ScreenshotButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_webcam; WebcamButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_terminal; TerminalButton { shell: catalog.shell; Layout.fillHeight: true } }
    Component { id: mod_converter; ConverterButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_sudoku; SudokuButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_games; GameButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_appmenu; AppMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_battery; BatteryButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_spotlight; BarButton { shell: catalog.shell; css: "spotlight"; text: "󰍉"; symbol: "system-search"; symbolContext: "actions"; fixedWidth: catalog.controlButtonStep; Layout.fillHeight: true; onClicked: catalog.shell.togglePopup("spotlight", true) } }
    Component { id: mod_task_view; BarButton { shell: catalog.shell; css: "task-view"; text: ""; symbol: "focus-windows"; symbolContext: "actions"; tooltip: "Task view"; fixedWidth: catalog.controlButtonStep; Layout.fillHeight: true; onClicked: catalog.shell.expose?.open() } }
    Component { id: mod_controlcenter; ControlCenter { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_nowplaying; NowPlaying { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_sound; SoundMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_wifi_menu; WifiMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_bluetooth_menu; BluetoothMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_vpn_menu; VpnMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_language_menu; LanguageMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_mirroring_menu; MirroringMenu { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_display_menu; DisplayMenu { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_winbar_weather; BarButton {
        id: weatherButton
        readonly property var readouts: Weather.output.readouts ?? {}
        readonly property bool small: catalog.shell.prefs.winbarSmall
        readonly property bool badge: small || catalog.shell.prefs.winbarWeatherBadge
        shell: catalog.shell; css: badge ? "weather.badge" : "weather"; leadingIcon: badge ? "" : readouts.current?.icon ?? ""; iconSize: badge ? catalog.appIconSize : 0; Layout.fillHeight: true
        text: badge ? readouts.current?.icon ?? "" : readouts.current && readouts.condition ? readouts.current.value + "\n" + readouts.condition.value : ""
        badgeText: badge ? readouts.current?.value.replace(/[CF]$/, "") ?? "" : ""
        onClicked: button => button === Qt.RightButton && !small
            ? catalog.shell.prefs.winbarWeatherBadge = !catalog.shell.prefs.winbarWeatherBadge
            : catalog.shell.togglePopup("weather")
        WeatherPopup { anchorItem: weatherButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed }
    } }
    Component { id: mod_launcher_strip; BarButton {
        readonly property bool shown: true
        shell: catalog.shell; css: "launcher-strip"; Layout.fillHeight: true
        onHoveredChanged: if (hovered) catalog.shell.run([catalog.shell.home + "/.local/lib/hypr/rofi/rofi-launch.sh", "d"])
    } }
    Component { id: mod_notification_center; NotificationCenter { shell: catalog.shell; kind: catalog.shell.clockKind; css: "datetime"; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }

}

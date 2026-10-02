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
        "appearance": mod_appearance, "colorpicker": mod_colorpicker, "powerprofile": mod_powerprofile, "powerbutton": mod_powerbutton,
        "bitwarden": mod_bitwarden, "github": mod_github, "privacy": mod_privacy, "language": mod_language,
        "hyprsunset": mod_hyprsunset, "caffeine": mod_caffeine, "screenrecord": mod_screenrecord,
        "screenshot": mod_screenshot, "webcam": mod_webcam, "terminal": mod_terminal,
        "converter": mod_converter, "sudoku": mod_sudoku, "games": mod_games,
        "appmenu": mod_appmenu, "battery": mod_battery, "spotlight": mod_spotlight, "controlcenter": mod_controlcenter, "nowplaying": mod_nowplaying, "sound-menu": mod_sound,
        "wifi-menu": mod_wifi_menu, "bluetooth-menu": mod_bluetooth_menu, "vpn-menu": mod_vpn_menu, "language-menu": mod_language_menu, "mirroring-menu": mod_mirroring_menu, "display-menu": mod_display_menu,
        "notification-center": mod_notification_center,
        "expose-strip": mod_expose_strip
    })

    Component { id: mod_menu; StartButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
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
    Component { id: mod_appearance; AppearanceGroup { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; reverse: true; Layout.fillHeight: true } }
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
    Component { id: mod_spotlight; BarButton { shell: catalog.shell; css: "spotlight"; text: "󰍉"; symbol: "system-search"; symbolContext: "actions"; Layout.fillHeight: true; onClicked: catalog.shell.togglePopup("spotlight", true) } }
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
        shell: catalog.shell; css: "weather"; leadingIcon: readouts.current?.icon ?? ""; Layout.fillHeight: true
        text: readouts.current && readouts.condition ? readouts.current.value + "\n" + readouts.condition.value : ""
        onClicked: catalog.shell.togglePopup("weather")
        WeatherPopup { anchorItem: weatherButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed }
    } }
    Component { id: mod_expose_strip; BarButton {
        readonly property bool shown: true
        shell: catalog.shell; css: "expose-strip"; Layout.fillHeight: true
        onHoveredChanged: if (hovered) catalog.shell.expose?.open()
    } }
    Component { id: mod_notification_center; NotificationCenter { shell: catalog.shell; kind: catalog.shell.clockKind; css: "datetime"; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }

}

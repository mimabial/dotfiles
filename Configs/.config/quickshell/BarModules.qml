pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "modules"
import qs.systemstats

Item {
    id: catalog
    required property var shell
    required property bool popupsAllowed
    readonly property bool vertical: shell.mode === "vertical"
    readonly property bool winbar: shell.mode === "winbar"
    readonly property bool horizontal: shell.mode === "horizontal"
    readonly property var registry: ({
        "menu": mod_menu, "taskbar": mod_taskbar, "workspaces": mod_workspaces, "submap": mod_submap,
        "tray": winbar ? mod_winbar_tray : mod_tray, "workspace-weather": mod_workspace_weather,
        "mediaplayer": vertical ? mod_stacked_media : mod_media, "datetime": vertical ? mod_datetime_group : mod_datetime,
        "date": mod_date, "weather": vertical ? mod_forecast : mod_weather, "forecast": mod_forecast,
        "systemstats": mod_systemstats, "cpu": mod_cpu, "gpu": mod_gpu, "memory": mod_memory,
        "disk": mod_disk, "fan": mod_fan, "minmax": mod_minmax, "agents": mod_agents,
        "wifi": mod_wifi, "speed": mod_speed, "bluetooth": mod_bluetooth, "vpn": mod_vpn,
        "printers": mod_printers, "removable": mod_removable, "volume": mod_volume, "microphone": mod_microphone,
        "display": mod_display, "updates": mod_updates, "notifications": mod_notifications, "tasks": mod_tasks,
        "appearance": mod_appearance, "colorpicker": mod_colorpicker, "powerprofile": mod_powerprofile, "powerbutton": mod_powerbutton,
        "bitwarden": mod_bitwarden, "github": mod_github, "privacy": mod_privacy, "language": mod_language,
        "hyprsunset": mod_hyprsunset, "caffeine": mod_caffeine, "screenrecord": mod_screenrecord,
        "screenshot": mod_screenshot, "webcam": mod_webcam, "terminal": mod_terminal,
        "converter": mod_converter, "sudoku": mod_sudoku, "games": mod_games
    })

    Component { id: mod_menu; StartButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_taskbar; WindowList { shell: catalog.shell; allWorkspaces: catalog.horizontal; framed: catalog.horizontal; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_workspaces; Workspaces { shell: catalog.shell; vertical: catalog.vertical; activeOnly: !catalog.winbar; hideActive: catalog.winbar; popupEnabled: !catalog.winbar && catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_submap; SubmapButton { shell: catalog.shell; alt: !catalog.vertical; baseColor: catalog.vertical ? catalog.shell.foreground : catalog.shell.alpha(catalog.shell.role("br", catalog.shell.foreground), .7); Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_tray; Tray { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; framed: catalog.horizontal || catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_stacked_media; MediaplayerButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_media; MediaButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_datetime_group; DatetimeGroup { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_datetime; ClockButton { shell: catalog.shell; kind: catalog.winbar ? "winbar" : "top"; css: "datetime"; textColor: catalog.winbar ? catalog.shell.foreground : catalog.shell.accent; popupEnabled: catalog.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_date; DateButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_forecast; ForecastGroup { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_weather; BarButton { id: weatherButton; shell: catalog.shell; css: "weather"; text: Weather.output.text; Layout.fillHeight: true; onClicked: catalog.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed } } }
    Component { id: mod_systemstats; SystemStats { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_cpu; CpuReadout { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_gpu; GpuReadout { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_memory; MemoryReadout { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_disk; DiskReadout { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_fan; FanReadout { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_minmax; MinmaxButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_agents; AgentsButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_wifi; WifiButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_speed; SpeedButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_bluetooth; BluetoothButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_vpn; VpnButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_printers; PrintersButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_removable; RemovableButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_volume; AudioButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_microphone; MicrophoneButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_display; DisplayButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_updates; UpdatesButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_notifications; NotificationButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; indicator: "dnd"; polling: false; showBadge: false; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical; Component.onCompleted: refresh() } }
    Component { id: mod_tasks; TasksButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_appearance; AppearanceGroup { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; vertical: catalog.vertical; reverse: !catalog.vertical; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_colorpicker; ColorPickerButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_powerprofile; PowerProfileButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_powerbutton; LogoutButton { shell: catalog.shell; text: ""; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_bitwarden; BitwardenButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_github; GithubButton { shell: catalog.shell; popupEnabled: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_privacy; PrivacyButton { shell: catalog.shell; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_language; LanguageButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_hyprsunset; HyprsunsetButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_caffeine; CaffeineButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_screenrecord; ScreenRecordButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_screenshot; ScreenshotButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_webcam; WebcamButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_terminal; TerminalButton { shell: catalog.shell; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_converter; ConverterButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_sudoku; SudokuButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }
    Component { id: mod_games; GameButton { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillWidth: catalog.vertical; Layout.fillHeight: !catalog.vertical } }

    Component { id: mod_workspace_weather; BarGroup {
        shell: catalog.shell; css: "workspace-weather"; vertical: false; Layout.fillHeight: true; holdOpen: catalog.shell.popupName === "weather"; preload: true
        slots: [activeWsSlot, sunriseSlot, minmaxSlot, weatherSlot]
        Component { id: activeWsSlot; Workspaces { shell: catalog.shell; activeOnly: true; Layout.fillHeight: true } }
        Component { id: sunriseSlot; ScriptButton { Layout.fillHeight: true; shell: catalog.shell; css: "weather.sunrise"; command: ["hyprshell", "weather", "-s", "--alt"]; interval: 3600000 } }
        Component { id: minmaxSlot; ScriptButton { Layout.fillHeight: true; shell: catalog.shell; css: "weather.minmax-only-alt"; command: ["hyprshell", "weather", "-m", "--temps-only", "--alt"]; interval: 3600000 } }
        Component { id: weatherSlot; BarButton { id: weatherButton; Layout.fillHeight: true; shell: catalog.shell; css: "weather"; text: Weather.output.text || ""; onClicked: catalog.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: catalog.shell; popupEnabled: catalog.popupsAllowed } } }
    } }
    Component { id: mod_winbar_tray; BarGroup {
        shell: catalog.shell; css: "tray-group"; vertical: false; Layout.fillHeight: true; reverse: true
        holdOpen: ["cpu", "gpu", "memory", "disk"].includes(catalog.shell.popupName)
        slots: [traySlot, trayCpuSlot, trayGpuSlot, trayMemSlot, trayDiskSlot]
        Component { id: traySlot; Tray { shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; Layout.fillHeight: true } }
        Component { id: trayCpuSlot; CpuReadout { Layout.fillHeight: true; shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000 } }
        Component { id: trayGpuSlot; GpuReadout { Layout.fillHeight: true; shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000 } }
        Component { id: trayMemSlot; MemoryReadout { Layout.fillHeight: true; shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 30000 } }
        Component { id: trayDiskSlot; DiskReadout { Layout.fillHeight: true; shell: catalog.shell; popupsAllowed: catalog.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 600000 } }
    } }
}

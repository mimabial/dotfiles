import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
    readonly property var registry: ({"menu": mod_menu, "taskbar": mod_taskbar, "tray": mod_tray, "updates": mod_updates, "agents": mod_agents, "gpu": mod_gpu, "cpu": mod_cpu, "memory": mod_memory, "disk": mod_disk, "fan": mod_fan, "minmax": mod_minmax, "dmark": mod_dmark, "wifi": mod_wifi, "speed": mod_speed, "bluetooth": mod_bluetooth, "vpn": mod_vpn, "printers": mod_printers, "disks": mod_disks, "connectivity": mod_connectivity, "barlayout": mod_barlayout, "colormode": mod_colormode, "wallpaper": mod_wallpaper, "converter": mod_converter, "tools": mod_tools, "sudoku": mod_sudoku, "datetime": mod_datetime, "date": mod_date, "eyecare": mod_eyecare, "forecast": mod_forecast, "info": mod_info, "info-drawer": mod_info_drawer, "mark": mod_mark, "mediaplayer": mod_mediaplayer, "notification": mod_notification, "dunst": mod_dunst, "power": mod_power, "privacybutton": mod_privacybutton, "screen": mod_screen, "screenshot": mod_screenshot, "screenrecord": mod_screenrecord, "terminal": mod_terminal, "audio": mod_audio, "submap": mod_submap, "workspaces": mod_workspaces})
    readonly property var layout: shell.barLayout
    readonly property bool hasSudoku: (layout || []).some(entry =>
        (typeof entry === "string" ? entry : String(entry.id || "")) === "sudoku")
    readonly property var section: shell.style.box(".modules-left")
    implicitWidth: mainColumn.implicitWidth + section.margin[1] + section.margin[3] + section.padding[1] + section.padding[3]
    color: shell.barColor
    exclusionMode: active ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-bar"
    WlrLayershell.layer: WlrLayer.Top
    readonly property bool popupOpen: shell.popupName !== "" && popupsAllowed
    property bool exclusivePhase: false
    WlrLayershell.keyboardFocus: !popupOpen ? WlrKeyboardFocus.None
        : exclusivePhase || shell.popupTyping ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    onPopupOpenChanged: {
        if (!popupOpen) return
        exclusivePhase = true
        shell.focusPriming = true
        focusPrime.restart()
        focusSettle.restart()
    }
    // the compositor focuses this surface, not the popup's own window
    Item {
        anchors.fill: parent; focus: true
        Keys.onPressed: event => { if (root.shell.popupCard) event.accepted = root.shell.popupCard.handleKey(event) }
    }
    Timer { id: focusPrime; interval: 150; onTriggered: root.exclusivePhase = false }
    // the grab settles a little after the mode drops back
    Timer { id: focusSettle; interval: 450; onTriggered: root.shell.focusPriming = false }

    Component { id: mod_menu; StartButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_taskbar; WindowList { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_tray; Tray { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_notification; NotificationGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; reverse: root.shell.layoutName === "main"; Layout.fillWidth: true } }
    Component { id: mod_dunst; DunstButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screen; ScreenGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screenshot; ScreenshotButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_screenrecord; ScreenRecordButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_terminal; TerminalButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_converter; ConverterButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_tools; ToolsGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_sudoku; SudokuButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_barlayout; BarLayoutGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_colormode; ColorModeGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_wallpaper; WallpaperGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_eyecare; EyecareGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_audio; AudioGroup { shell: root.shell; reverse: true; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_privacybutton; PrivacyButton { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_mediaplayer; MediaplayerButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_datetime; DatetimeGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_date; BarButton { id: dateButton; property string dateFormat: "ddd\ndd\nMMM"; property string dateFormatAlt: "dd|\nMM|\nyy "; shell: root.shell; css: "clock.date"; text: Qt.formatDate(root.shell.clock.date, root.shell.store.mainDateNumeric ? dateButton.dateFormatAlt : dateButton.dateFormat); onClicked: button => button === Qt.RightButton ? root.shell.store.mainDateNumeric = !root.shell.store.mainDateNumeric : root.shell.togglePopup("clock"); Layout.fillWidth: true; ClockPopup { anchorItem: dateButton; shell: dateButton.shell; popupEnabled: root.popupsAllowed } } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; vertical: true; activeOnly: true; popupEnabled: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_submap; SubmapButton { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_forecast; ForecastGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_mark; MarkGroup { shell: root.shell; Layout.fillWidth: true } }
    Component { id: mod_info; InfoGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; single: root.shell.layoutName === "main"; Layout.fillWidth: true } }
    Component { id: mod_info_drawer; InfoDrawerGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_updates; UpdatesGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_agents; UpdatesGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; agentsFirst: true; Layout.fillWidth: true } }
    Component { id: mod_gpu; GpuReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_cpu; CpuReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_memory; MemoryReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_disk; DiskReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_fan; FanReadout { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_minmax; MinmaxButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_dmark; DmarkButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_wifi; WifiGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_bluetooth; BluetoothGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_speed; SpeedButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_vpn; VpnButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_printers; PrintersButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_disks; DisksGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_connectivity; ConnectivityGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    Component { id: mod_power; PowerGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillWidth: true } }
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.leftMargin: root.section.margin[3] + root.section.padding[3]; anchors.rightMargin: root.section.margin[1] + root.section.padding[1]
        anchors.topMargin: root.section.margin[0] + root.section.padding[0]; anchors.bottomMargin: root.section.margin[2] + root.section.padding[2]
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

    // the menu's Sudoku entry opens the popup by name, but no layout carries a
    // sudoku module to host it, so the bar hosts one itself when the layout does
    // not. Loaded on first open, like SudokuButton does it
    Loader {
        id: sudokuHost
        property bool loaded: false
        active: loaded && !root.hasSudoku
        visible: false
        sourceComponent: Component { SudokuPopup { anchorItem: mainColumn; shell: root.shell; popupEnabled: root.popupsAllowed } }
        Connections {
            target: root.shell
            function onPopupNameChanged() {
                if (root.popupsAllowed && !root.hasSudoku && root.shell.popupName === "sudoku") sudokuHost.loaded = true
            }
        }
    }
}

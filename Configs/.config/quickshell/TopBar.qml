import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var shell
    readonly property var section: shell.style.box(".modules-left")
    readonly property var layout: shell.barLayout
    readonly property var registry: ({"taskbar": mod_taskbar, "mediaplayer": mod_mediaplayer, "datetime": mod_datetime, "mark-left": mod_mark_left, "workspaces": mod_workspaces, "mark-right": mod_mark_right, "weather": mod_weather, "submap": mod_submap, "status": mod_status, "monitor": mod_monitor, "screen": mod_screen, "notification": mod_notification, "privacybutton": mod_privacy, "tray": mod_tray, "power": mod_power})
    property bool active: shell.mode === "top" && !shell.userHidden
    // only the focused monitor's instance may own a panel: two focus grabs
    // cancel each other, which reads as the popup refusing to open
    readonly property bool popupsAllowed: active && (!Hyprland.focusedMonitor
        || !screen || Hyprland.focusedMonitor.name === screen.name)
    anchors.left: true; anchors.right: true; anchors.top: true
    margins.top: active ? 0 : -implicitHeight
    implicitHeight: Math.max(leftRow.implicitHeight, centerRow.implicitHeight, rightRow.implicitHeight)
    color: shell.barColor
    exclusionMode: active ? ExclusionMode.Auto : ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-bar"
    WlrLayershell.layer: WlrLayer.Top
    readonly property bool popupOpen: shell.popupName !== "" && popupsAllowed
    property bool exclusivePhase: false
    // a click routes focus into an xdg-popup by itself; a panel summoned by
    // keybind does not, so prime Exclusive briefly then fall back — an
    // exclusive surface swallows pointer events on every monitor
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

    Component { id: mod_taskbar; WindowList { shell: root.shell; allWorkspaces: true; framed: true; Layout.fillHeight: true } }
    Component { id: mod_mediaplayer; MediaButton { shell: root.shell; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }
    Component { id: mod_datetime; ClockButton { shell: root.shell; kind: "top"; css: "clock.time-alt"; Layout.fillHeight: true; fontWeight: Font.Bold; textColor: root.shell.accent; popupEnabled: root.popupsAllowed } }
    Component { id: mod_mark_left; BarButton { shell: root.shell; css: "custom-tmark.left"; text: "󱘹"; Layout.fillHeight: true } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; activeOnly: true; numerals: "roman"; Layout.fillHeight: true } }
    Component { id: mod_mark_right; BarButton { shell: root.shell; css: "custom-tmark.right"; text: "󱘹"; Layout.fillHeight: true } }
    Component { id: mod_weather; BarButton { id: weatherButton; shell: root.shell; css: "custom-weather"; text: Weather.output.text; Layout.fillHeight: true; textColor: root.shell.role("c2", root.shell.foreground); onClicked: root.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    Component { id: mod_submap; ScriptButton { shell: root.shell; css: "custom-submap"; command: ["hyprshell", "keybinds/submap-status", "--alt"]; interval: 86400000; Layout.fillHeight: true; textColor: root.shell.alpha(root.shell.role("br", root.shell.foreground), .7) } }
    Component { id: mod_status; Status { shell: root.shell; vertical: false; Layout.fillHeight: true; showNetwork: false; showPower: false; showLogout: false; popupsEnabled: root.popupsAllowed } }
    Component { id: mod_monitor; DrawerGroup {
        shell: root.shell; vertical: false; reverse: true; Layout.fillHeight: true
        primary: Component { BarButton { id: monitorButton; shell: root.shell; css: "backlight"; text: "󰃠"; Layout.fillHeight: true; radius: root.shell.moduleRadius; onClicked: root.shell.togglePopup("monitor"); onWheeled: delta => root.shell.run(["hyprshell", "brightness-control.sh", delta > 0 ? "i" : "d"]); MonitorPopup { anchorItem: monitorButton; shell: root.shell; popupEnabled: root.popupsAllowed } } }
        secondary: Component { ScriptButton { shell: root.shell; css: "custom-hyprsunset"; Layout.fillHeight: true; radius: root.shell.moduleRadius; command: ["hyprshell", "hyprsunset", "-rq"]; interval: 86400000; onClicked: root.shell.run(["hyprshell", "hyprsunset", "-t", "-P", "waybar:19"]) } }
    } }
    Component { id: mod_screen; DrawerGroup {
        shell: root.shell; css: "screen-group"; vertical: false; reverse: true; Layout.fillHeight: true; radius: root.shell.moduleRadius; fill: root.shell.alpha(root.shell.background, .1)
        primary: Component { ScriptButton { shell: root.shell; css: "custom-screenrecord"; Layout.fillHeight: true; textColor: root.shell.role(output.class === "recording" ? "error" : "c1", root.shell.foreground); command: ["hyprshell", "screenrecord", "--status"]; interval: 1000; onClicked: button => root.shell.run(["hyprshell", "screenrecord", button === Qt.RightButton ? "--quit" : "--toggle"]) } }
        secondary: Component { RowLayout { spacing: 0
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "custom-colorpicker"; command: ["hyprshell", "color-picker.sh", "-j"]; interval: 86400000; onClicked: root.shell.run(["hyprshell", "color-picker.sh"]); onWheeled: delta => root.shell.run(["hyprshell", "color-picker.sh", delta > 0 ? "-u" : "-d"]) }
            BarButton { Layout.fillHeight: true; shell: root.shell; css: "custom-screenshot"; text: "󰄄"; tooltip: "<b>Screenshot</b>\nLeft: Select area\nMiddle: Full screen\nRight: Focused monitor"; onClicked: button => root.shell.run(["hyprshell", "screenshot", button === Qt.MiddleButton ? "p" : button === Qt.RightButton ? "m" : "smart"]) }
        } }
    } }
    Component { id: mod_notification; DrawerGroup {
        shell: root.shell; css: "notification-group"; vertical: false; reverse: true; Layout.fillHeight: true; radius: root.shell.moduleRadius; fill: root.shell.alpha(root.shell.background, .1)
        primary: Component { NotificationButton { shell: root.shell; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }
        secondary: Component { ScriptButton { shell: root.shell; css: "custom-github.notifications"; Layout.fillHeight: true; textColor: root.shell.role(output.class === "degraded" ? "warning" : output.class === "error" ? "error" : "success", root.shell.foreground); command: ["hyprshell", "github-notifications"]; interval: 3600000; onClicked: root.shell.run(["xdg-open", "https://github.com/notifications"]) } }
    } }
    Component { id: mod_privacy; PrivacyButton { shell: root.shell; Layout.fillHeight: true } }
    Component { id: mod_tray; Tray { shell: root.shell; framed: true; iconSize: 18; iconSpacing: 10; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_power; Item {
        readonly property var box: root.shell.style.box("power-group")
        Layout.fillHeight: true; implicitWidth: powerStatus.implicitWidth; implicitHeight: powerStatus.implicitHeight
        Rectangle { anchors.fill: parent; anchors.topMargin: parent.box.margin[0]; anchors.rightMargin: parent.box.margin[1]; anchors.bottomMargin: parent.box.margin[2]; anchors.leftMargin: parent.box.margin[3]; radius: root.shell.moduleRadius; color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .1); border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .3); border.width: topPowerEdge.replacesOutline ? 0 : Math.max(1, parent.box.border) }
        Status { id: powerStatus; shell: root.shell; vertical: false; showAudio: false; showNetwork: false; popupsEnabled: root.popupsAllowed; anchors.fill: parent; anchors.topMargin: parent.box.margin[0] + parent.box.padding[0]; anchors.rightMargin: parent.box.margin[1] + parent.box.padding[1]; anchors.bottomMargin: parent.box.margin[2] + parent.box.padding[2]; anchors.leftMargin: parent.box.margin[3] + parent.box.padding[3] }
        ModuleEdge { id: topPowerEdge; shell: root.shell }
    } }

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.leftMargin: root.section.margin[3]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.left || []
    }
    BarSection {
        id: centerRow
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.center || []
    }
    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.rightMargin: root.section.margin[1]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.right || []
    }
}

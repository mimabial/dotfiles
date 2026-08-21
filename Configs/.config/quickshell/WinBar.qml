import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "modules"

PanelWindow {
    id: root
    required property var shell
    readonly property var section: shell.style.box(".modules-left")
    readonly property var layout: shell.barLayout
    readonly property var registry: ({"menu": mod_menu, "taskbar": mod_taskbar, "active": mod_active, "workspaces": mod_workspaces, "tray": mod_tray, "language": mod_language, "datetime": mod_datetime})
    property bool active: shell.mode === "winbar" && !shell.userHidden
    // only the focused monitor's instance may own a panel: two focus grabs
    // cancel each other, which reads as the popup refusing to open
    readonly property bool popupsAllowed: active && (!Hyprland.focusedMonitor
        || !screen || Hyprland.focusedMonitor.name === screen.name)
    anchors.left: true; anchors.right: true; anchors.bottom: true
    margins.bottom: active ? 0 : -implicitHeight
    implicitHeight: Math.max(44 * Style.scale, leftRow.implicitHeight, centerWorkspaces.implicitHeight, rightRow.implicitHeight)
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

    Component { id: mod_menu; StartButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_taskbar; WindowList { shell: root.shell; Layout.fillHeight: true } }
    Component { id: mod_active; DrawerGroup {
        shell: root.shell; css: "active-group"; vertical: false; Layout.fillHeight: true; holdOpen: root.shell.popupName === "weather"
        primary: Component { Workspaces { shell: root.shell; activeOnly: true; Layout.fillHeight: true } }
        secondary: Component { RowLayout { spacing: 0
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "custom-weather.sunrise"; command: ["hyprshell", "weather", "-s", "--alt"]; interval: 3600000 }
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "custom-weather.minmax-only-alt"; command: ["hyprshell", "weather", "-m", "--temps-only", "--alt"]; interval: 3600000 }
            BarButton { id: weatherButton; Layout.fillHeight: true; shell: root.shell; css: "custom-weather"; text: Weather.output.text || ""; onClicked: root.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed } }
        } }
    } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; hideActive: true; Layout.fillHeight: true } }
    Component { id: mod_tray; DrawerGroup {
        shell: root.shell; css: "tray-group"; vertical: false; Layout.fillHeight: true; reverse: true
        primary: Component { Tray { shell: root.shell; iconSize: 18; iconSpacing: 6; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
        secondary: Component { RowLayout { spacing: 0
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "custom-cpuinfo"; command: ["hyprshell", "cpuinfo"]; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000; textColor: root.shell.role("c7", root.shell.foreground) }
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "custom-gpuinfo"; command: ["hyprshell", "gpuinfo"]; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000; textColor: root.shell.role("c7", root.shell.foreground); onClicked: button => root.shell.run(["hyprshell", "gpuinfo", button === Qt.RightButton ? "--reset" : "--toggle"]) }
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "memory"; command: ["hyprshell", "sysinfo/meminfo"]; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 30000; textColor: root.shell.role("c7", root.shell.foreground) }
            ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "disk"; command: ["hyprshell", "sysinfo/diskinfo"]; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 600000; textColor: root.shell.role("c7", root.shell.foreground) }
        } }
    } }
    Component { id: mod_language; LanguageModule { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_datetime; ClockButton { shell: root.shell; kind: "winbar"; css: "clock.datetime-winbar"; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.leftMargin: root.section.margin[3]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.left || []
    }

    BarSection {
        id: centerWorkspaces
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.center || []
    }

    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.rightMargin: root.section.margin[1]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.right || []
    }
}

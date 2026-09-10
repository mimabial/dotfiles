import QtQuick
import QtQuick.Layouts
import "modules"

BarSurface {
    id: root
    readonly property var section: shell.style.box(".modules-left")
    readonly property var layout: shell.barLayout
    readonly property bool onTop: shell.barEdge === "top"
    readonly property var registry: ({"menu": mod_menu, "taskbar": mod_taskbar, "workspace-weather": mod_workspace_weather, "workspaces": mod_workspaces, "mediaplayer": mod_mediaplayer, "tray": mod_tray, "language": mod_language, "datetime": mod_datetime, "converter": mod_converter, "sudoku": mod_sudoku, "submap": mod_submap})
    active: shell.mode === "winbar" && !shell.userHidden
    anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
    margins.top: onTop ? (active ? 0 : -implicitHeight) : 0
    margins.bottom: onTop ? 0 : (active ? 0 : -implicitHeight)
    implicitHeight: Math.max(leftRow.implicitHeight, centerWorkspaces.implicitHeight, rightRow.implicitHeight)
    Component { id: mod_menu; StartButton { shell: root.shell; popupEnabled: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_taskbar; WindowList { shell: root.shell; Layout.fillHeight: true } }
    Component { id: mod_workspace_weather; BarGroup {
        shell: root.shell; css: "workspace-weather"; vertical: false; Layout.fillHeight: true; holdOpen: root.shell.popupName === "weather"; preload: true
        slots: [activeWsSlot, sunriseSlot, minmaxSlot, weatherSlot]
        Component { id: activeWsSlot; Workspaces { shell: root.shell; activeOnly: true; Layout.fillHeight: true } }
        Component { id: sunriseSlot; ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "weather.sunrise"; command: ["hyprshell", "weather", "-s", "--alt"]; interval: 3600000 } }
        Component { id: minmaxSlot; ScriptButton { Layout.fillHeight: true; shell: root.shell; css: "weather.minmax-only-alt"; command: ["hyprshell", "weather", "-m", "--temps-only", "--alt"]; interval: 3600000 } }
        Component { id: weatherSlot; BarButton { id: weatherButton; Layout.fillHeight: true; shell: root.shell; css: "weather"; text: Weather.output.text || ""; onClicked: root.shell.togglePopup("weather"); WeatherPopup { anchorItem: weatherButton; shell: root.shell; popupEnabled: root.popupsAllowed } } }
    } }
    Component { id: mod_workspaces; Workspaces { shell: root.shell; hideActive: true; Layout.fillHeight: true } }
    Component { id: mod_mediaplayer; MediaButton { shell: root.shell; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }
    Component { id: mod_tray; BarGroup {
        shell: root.shell; css: "tray-group"; vertical: false; Layout.fillHeight: true; reverse: true
        holdOpen: ["cpu", "gpu", "memory", "disk"].includes(root.shell.popupName)
        slots: [traySlot, trayCpuSlot, trayGpuSlot, trayMemSlot, trayDiskSlot]
        Component { id: traySlot; Tray { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
        Component { id: trayCpuSlot; CpuReadout { Layout.fillHeight: true; shell: root.shell; popupsAllowed: root.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000 } }
        Component { id: trayGpuSlot; GpuReadout { Layout.fillHeight: true; shell: root.shell; popupsAllowed: root.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 5000 } }
        Component { id: trayMemSlot; MemoryReadout { Layout.fillHeight: true; shell: root.shell; popupsAllowed: root.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 30000 } }
        Component { id: trayDiskSlot; DiskReadout { Layout.fillHeight: true; shell: root.shell; popupsAllowed: root.popupsAllowed; processEnvironment: ({ HYPR_SYSINFO_ALT: "1" }); interval: 600000 } }
    } }
    Component { id: mod_submap; SubmapButton { shell: root.shell; alt: true; Layout.fillHeight: true; baseColor: root.shell.alpha(root.shell.role("br", root.shell.foreground), .7) } }
    Component { id: mod_language; LanguageButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_datetime; ClockButton { shell: root.shell; kind: "winbar"; css: "clock.datetime-winbar"; Layout.fillHeight: true; popupEnabled: root.popupsAllowed } }
    Component { id: mod_converter; ConverterButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }
    Component { id: mod_sudoku; SudokuButton { shell: root.shell; popupsAllowed: root.popupsAllowed; Layout.fillHeight: true } }

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.leftMargin: root.section.margin[3] + root.section.padding[3]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.left || []
    }

    BarSection {
        id: centerWorkspaces
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.center || []
    }

    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.rightMargin: root.section.margin[1] + root.section.padding[1]; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.layout.right || []
    }

    PopupHost { shell: root.shell; anchorItem: leftRow; popupsAllowed: root.popupsAllowed }
}

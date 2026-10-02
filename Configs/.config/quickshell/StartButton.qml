import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "dock/DockModel.js" as DockModel
import "modules"
import "StartMenuModel.js" as StartMenuModel

BarButton {
    id: root
    property bool popupEnabled: true
    property bool dropdown: false
    property bool taskbarSettings: false
    property var recentItems: []
    css: "menu"; text: ""
    onDropdownChanged: menuTree.running = dropdown
    onClicked: button => {
        if (button === Qt.RightButton) {
            if (taskbarSettings) shell.togglePopup("winbar-settings")
            else shell.run(["hyprshell", "menutree"])
        } else if (button === Qt.MiddleButton) shell.run([shell.terminal])
        else shell.togglePopup(dropdown ? "hyprmenu" : "start")
    }
    StartPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    Bookmarks { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    MenuBarPopup {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.taskbarSettings
        popupName: "winbar-settings"
        items: open ? [
            {text: "Combine app windows", checked: root.shell.prefs.winbarCombine !== "never",
                run: () => root.shell.toggleWinbarCombine()},
            {text: "Automatically hide taskbar", checked: root.shell.prefs.winbarAutoHide,
                run: () => {
                    const enabled = !root.shell.prefs.winbarAutoHide
                    if (enabled) root.shell.barRevealed = true
                    root.shell.prefs.winbarAutoHide = enabled
                }}
        ] : []
    }
    function forceQuitItems() {
        const windows = Hyprland.toplevels?.values ?? []
        const items = windows.map(window => {
            const address = DockModel.windowAddress(window)
            if (!address) return null
            const appId = String(window.wayland?.appId || window.lastIpcObject?.class || "")
            const name = DesktopEntries.heuristicLookup(appId)?.name || appId || "Window"
            const title = String(window.title || "")
            return { text: title && title !== name ? name + " — " + title : name,
                run: () => Hyprland.dispatch(`hl.dsp.window.kill({window = "address:${address}"})`) }
        }).filter(Boolean)
        return items.length ? items : [{ text: "No open windows" }]
    }
    function appleItems(menus) {
        const selected = target => root.shell.menuTargetActive(target)
        const main = StartMenuModel.dropdownItems(menus, selected)
        const system = StartMenuModel.dropdownItems(menus, selected, "system")
        const action = target => system.find(item => item.run?.[3] === target)
        const power = ["system_lock", "system_suspend", "system_logout", "system_restart", "system_shutdown"]
            .map(target => {
                const item = action(target)
                if (!item) return null
                if (target === "system_restart" || target === "system_shutdown")
                    return { text: target === "system_restart" ? "Restart" : "Shut Down", run: item.run }
                return item
            }).filter(Boolean)
        const about = main.find(item => item.run?.[3] === "main_about")
        const recent = root.recentItems.map(item => ({ text: item.text, run: ["xdg-open", item.uri] }))
        return [
            ...(about ? [{ text: "About This Desktop", run: about.run }] : []),
            { text: "System Settings…", run: ["hyprshell", "window/settings"] },
            null,
            { text: "Recent Items", submenu: recent.length ? recent : [{ text: "No recent documents" }] },
            { text: "Force Quit…", submenu: forceQuitItems() },
            null,
            ...power,
            null,
            { text: "Hyprmenu", submenu: main }
        ]
    }
    MenuBarPopup {
        id: dropdownMenu
        property var menus: ({})
        items: open ? root.appleItems(menus) : []
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.dropdown; popupName: "hyprmenu"
        onOpenChanged: {
            if (open) { root.shell.refreshMenuState(); recentProcess.running = true }
            else menuTree.running = true
        }
        Process {
            id: menuTree
            command: ["hyprshell", "rofi/menutree", "--dump-json"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: dropdownMenu.menus = JSON.parse(text) }
        }
        Process {
            id: recentProcess
            command: ["python3", root.shell.home + "/.local/lib/hypr/quickshell/recent-items.py"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recentItems = JSON.parse(text) }
        }
    }
}

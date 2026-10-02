pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../dock/DockModel.js" as DockModel
import ".."

RowLayout {
    id: root
    required property var shell
    property bool popupsAllowed: true
    readonly property var focused: ToplevelManager.activeToplevel ? Hyprland.activeToplevel : null
    readonly property string appId: focused ? appIdOf(focused) : ""
    readonly property bool dolphinFocused: appId === "org.kde.dolphin" || appId === "dolphin"
    readonly property var fileManager: Array.from(DesktopEntries.applications.values).find(app => app.categories.includes("FileManager")) ?? null
    readonly property bool desktop: focused === null
    readonly property bool shown: !desktop || fileManager !== null
    readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : fileManager
    readonly property string appName: entry?.name || appId
    readonly property bool terminal: !!entry && entry.categories.includes("TerminalEmulator")
    readonly property var standardMenus: ["App", "File", "Edit", "View", "Window", "Help"]
    property var appMenus: ({})
    property var recentFolders: []
    readonly property var extraMenus: appMenus[appId.toLowerCase()] ?? {}
    readonly property string extraTitles: Object.keys(extraMenus).filter(title => !standardMenus.includes(title)).join("\n")
    readonly property var headings: desktop ? ["App", "File", "Go", "Help"]
        : standardMenus.slice(0, -2).concat(dolphinFocused ? ["Go"] : [], extraTitles ? extraTitles.split("\n") : [], "Window", "Help")
    spacing: 0

    function appIdOf(toplevel) { return String(toplevel.wayland?.appId || toplevel.lastIpcObject?.class || "") }
    function selector(toplevel) { return "address:" + DockModel.windowAddress(toplevel) }
    function dispatch(lua) { shell.run(["hyprctl", "dispatch", lua]) }
    function onFocused(dispatcher, args) { return () => dispatch(`hl.dsp.${dispatcher}({${args ? args + ", " : ""}window = "${selector(focused)}"})`) }
    function refreshRecentFolders() { recentFoldersProc.running = true }
    function computerItems() {
        const volumes = []
        for (const device of Removable.systemDevices.concat(Removable.devices))
            for (const volume of device.volumes)
                if (volume.mounted && volume.fstype !== "swap")
                    volumes.push({ text: volume.title || device.title, run: ["dolphin", volume.mountpoint] })
        return volumes.length ? volumes : [{ text: "No mounted drives" }]
    }
    function menuItems(title) {
        const keyLabels = { equal: "=", minus: "−", space: "Space", Left: "←", Right: "→", Up: "↑" }
        const keys = (text, mods, key, enabled = true) => ({ text, shortcut: title === "Edit" ? "" : mods.replace("CTRL", "⌃").replace("ALT", "⌥").replace("SHIFT", "⇧").replace(/ /g, "") + (keyLabels[key] ?? key),
            run: enabled ? onFocused("send_shortcut", `mods = "${mods}", key = "${key}"`) : null })
        if (title === "Go") return [
            ...(dolphinFocused ? [keys("Back", "ALT", "Left"), keys("Forward", "ALT", "Right"), keys("Enclosing Folder", "ALT", "Up"), null] : []),
            { text: "Recents", run: ["dolphin", "recentlyused:/"] }, null,
            ...["Home", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos"]
                .map(place => ({ text: place, run: dolphinFocused && place === "Home" ? onFocused("send_shortcut", 'mods = "ALT", key = "Home"')
                    : ["dolphin", place === "Home" ? shell.home : shell.home + "/" + place] })),
            null,
            { text: "Computer", submenu: computerItems() },
            { text: "Network", run: ["dolphin", "remote:/"] },
            { text: "Applications", run: ["dolphin", "applications:/"] },
            { text: "Utilities", run: ["dolphin", "applications:/Utilities/"] },
            null,
            { text: "Recent Folders", submenu: recentFolders.length ? recentFolders.map(folder => ({ text: folder.text, run: ["dolphin", folder.uri] })) : [{ text: "No recent folders" }] },
            { text: "Go to Folder…", shortcut: "⌃L", run: dolphinFocused ? onFocused("send_shortcut", 'mods = "CTRL", key = "L"')
                : [shell.home + "/.local/lib/hypr/rofi/location-prompt.sh", "Go to Folder"] },
            { text: "Connect to Server…", run: [shell.home + "/.local/lib/hypr/rofi/location-prompt.sh", "Connect to Server"] }
        ]
        const help = [
            ...(dolphinFocused ? [{ text: "Dolphin Help", run: ["xdg-open", "https://docs.kde.org/stable_kf6/en/dolphin/dolphin/"] }, null] : []),
            { text: "Search Menu Commands…", run: ["hyprshell", "rofi/menutree", "--search-all"] },
            { text: "Desktop Keyboard Shortcuts…", run: ["hyprshell", "keybinds/keybinds_hint"] }
        ]
        if (desktop) return ({
            App: [{ text: "Open Trash", run: ["xdg-open", "trash:///"] }],
            File: [{ text: "New " + appName + " Window", run: () => entry.execute() }],
            Help: help
        })[title] ?? []
        const separator = null, clipboard = terminal ? "CTRL SHIFT" : "CTRL"
        const windows = Hyprland.toplevels.values.filter(toplevel => appIdOf(toplevel) === appId)
        const minimize = toplevel => shell.dock?.minimizeToplevel(DockModel.windowAddress(toplevel))
        const actions = Array.from(entry?.actions ?? []).map(action => ({ text: action.name, run: () => action.execute() }))
        const standard = ({
            App: [
                { text: "Hide " + appName, run: () => windows.forEach(minimize) },
                separator,
                { text: "Quit " + appName, run: () => windows.forEach(toplevel => toplevel.wayland?.close()) }
            ],
            File: (actions.length ? actions : [{ text: "New Window", run: entry ? () => entry.execute() : null }])
                .concat([separator, { text: "Close Window", run: () => focused.wayland?.close() }]),
            Edit: [
                keys("Undo", "CTRL", "Z", !terminal), keys("Redo", "CTRL SHIFT", "Z", !terminal), separator,
                keys("Cut", "CTRL", "X", !terminal), keys("Copy", clipboard, "C"), keys("Paste", clipboard, "V"),
                keys("Select All", "CTRL", "A", !terminal)
            ],
            View: [{ text: "Toggle Full Screen", run: onFocused("window.fullscreen", 'mode = "fullscreen", action = "toggle"') }],
            Window: [
                { text: "Minimize", run: () => minimize(focused) },
                { text: "Zoom", run: onFocused("window.fullscreen", 'mode = "maximized", action = "toggle"') },
                { text: "Toggle Floating", run: onFocused("window.float", 'action = "toggle"') },
                { text: "Center", run: onFocused("window.center") },
                separator
            ].concat(windows.map(toplevel => ({ text: toplevel.title, checked: toplevel === focused,
                run: () => dispatch(`hl.dsp.focus({window = "${selector(toplevel)}"})`) }))),
            Help: help
        })[title] ?? []
        const custom = Array.from(extraMenus[title] ?? []).map(item => item && keys(item[0], item[1] ?? "", item[2] ?? "", item.length > 1))
        const overridden = standard.map(item => custom.find(entry => entry?.text === item?.text) ?? item)
        const added = custom.filter(entry => !standard.some(item => item && item.text === entry?.text))
        return overridden.concat(standard.length && added.length ? [separator] : [], added)
    }

    FileView {
        path: root.shell.home + "/.config/quickshell/appmenus.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const menus = {}, data = JSON.parse(text())
            for (const ids in data) for (const id of ids.split(",")) menus[id.trim().toLowerCase()] = data[ids]
            root.appMenus = menus
        }
    }
    Process {
        id: recentFoldersProc
        command: ["python3", root.shell.home + "/.local/lib/hypr/quickshell/recent-items.py", "folders"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recentFolders = JSON.parse(text) }
    }
    Binding { target: root.shell; property: "menuBarHeadings"; value: root.headings; when: root.popupsAllowed && root.shell.layoutName === "macos" }
    Repeater {
        model: root.headings
        BarButton {
            id: title
            required property string modelData
            Layout.fillHeight: true
            shell: root.shell
            css: modelData === "App" ? "appmenu.app" : "appmenu"
            text: modelData === "App" ? root.appName : modelData
            onClicked: shell.togglePopup(menu.popupName)
            MenuBarPopup {
                id: menu
                anchorItem: title; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "appmenu:" + title.modelData
                items: open ? root.menuItems(title.modelData) : []
            }
            Connections {
                target: title.modelData === "Go" ? menu : null
                function onOpenChanged() { if (menu.open) root.refreshRecentFolders() }
            }
        }
    }
}

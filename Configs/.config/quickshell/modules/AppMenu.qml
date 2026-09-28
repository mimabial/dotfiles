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
    readonly property var fileManager: Array.from(DesktopEntries.applications.values).find(app => app.categories.includes("FileManager")) ?? null
    readonly property bool desktop: focused === null
    readonly property bool shown: !desktop || fileManager !== null
    readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : fileManager
    readonly property string appName: entry?.name || appId
    readonly property bool terminal: !!entry && entry.categories.includes("TerminalEmulator")
    readonly property var standardMenus: ["App", "File", "Edit", "View", "Window"]
    property var appMenus: ({})
    readonly property var extraMenus: appMenus[appId.toLowerCase()] ?? {}
    readonly property string extraTitles: Object.keys(extraMenus).filter(title => !standardMenus.includes(title)).join("\n")
    spacing: 0

    function appIdOf(toplevel) { return String(toplevel.wayland?.appId || toplevel.lastIpcObject?.class || "") }
    function selector(toplevel) { return "address:" + DockModel.windowAddress(toplevel) }
    function dispatch(lua) { shell.run(["hyprctl", "dispatch", lua]) }
    function onFocused(dispatcher, args) { return () => dispatch(`hl.dsp.${dispatcher}({${args ? args + ", " : ""}window = "${selector(focused)}"})`) }
    function menuItems(title) {
        if (desktop) return ({
            App: [{ text: "Open Trash", run: ["xdg-open", "trash:///"] }],
            File: [{ text: "New " + appName + " Window", run: () => entry.execute() }],
            Go: ["Home", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos"]
                .map(place => ({ text: place, run: ["xdg-open", place === "Home" ? shell.home : shell.home + "/" + place] }))
        })[title] ?? []
        const separator = null, clipboard = terminal ? "CTRL SHIFT" : "CTRL"
        const windows = Hyprland.toplevels.values.filter(toplevel => appIdOf(toplevel) === appId)
        const minimize = toplevel => shell.dock?.minimizeToplevel(DockModel.windowAddress(toplevel))
        const actions = Array.from(entry?.actions ?? []).map(action => ({ text: action.name, run: () => action.execute() }))
        const keyLabels = { equal: "=", minus: "−", space: "Space" }
        const keys = (text, mods, key, enabled = true) => ({ text, shortcut: mods.replace("CTRL", "⌃").replace("ALT", "⌥").replace("SHIFT", "⇧").replace(/ /g, "") + (keyLabels[key] ?? key),
            run: enabled ? onFocused("send_shortcut", `mods = "${mods}", key = "${key}"`) : null })
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
                run: () => dispatch(`hl.dsp.focus({window = "${selector(toplevel)}"})`) })))
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
    Repeater {
        model: root.desktop ? ["App", "File", "Go"] : root.standardMenus.slice(0, -1).concat(root.extraTitles ? root.extraTitles.split("\n") : [], "Window")
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
        }
    }
}

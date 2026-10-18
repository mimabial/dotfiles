.pragma library

var SECTIONS = ["left", "center", "right", "tray"]
var LABELS = { left: "Left", center: "Center", right: "Right", tray: "Tray" }
var WIDGET_NAMES = { altscape: "Alt+Tab" }
var DESCRIPTIONS = {
    "menu": "Apps and system actions",
    "taskbar": "Running and pinned apps",
    "workspaces": "Switch virtual desktops",
    "submap": "Active shortcut group",
    "tray": "Hidden widgets and app icons",
    "mediaplayer": "Playback and track controls",
    "datetime": "Time, date and calendar",
    "weather": "Forecast and conditions",
    "systemstats": "Resource usage and processes",
    "agents": "Coding agent usage limits",
    "wifi": "Wireless networks and connections",
    "bluetooth": "Pair and connect devices",
    "quickshare": "Send and receive Android files",
    "vpn": "Connection status and controls",
    "printers": "Print queues and jobs",
    "removable": "Connected drives and eject",
    "volume": "Output volume and devices",
    "microphone": "Input volume and mute",
    "display": "Brightness and monitor profiles",
    "updates": "Available package updates",
    "notifications": "Notification history and quiet mode",
    "tasks": "To-do lists and progress",
    "wallpaper": "Wallpaper selection and rotation",
    "colormode": "Light and dark theme modes",
    "barlayout": "Bar layout and desktop options",
    "windowlayout": "Window tiling and orientation",
    "workflows": "Desktop workflow presets",
    "colorpicker": "Pick and copy screen colors",
    "powerprofile": "Performance and energy modes",
    "powerbutton": "Lock, logout and power actions",
    "bitwarden": "Saved passwords and vault",
    "github": "GitHub notification inbox",
    "privacy": "Other apps capturing your screen",
    "language": "Keyboard layouts and variants",
    "hyprsunset": "Night light and color temperature",
    "caffeine": "Keep the display awake",
    "screenrecord": "Start and stop recordings",
    "screenshot": "Capture regions and windows",
    "webcam": "Camera preview and controls",
    "terminal": "Open Alacritty or Kitty",
    "converter": "Units and currency conversion",
    "sudoku": "Play number puzzles",
    "games": "Games and MangoHud controls",
    "appmenu": "Active app menus and actions",
    "battery": "Charge status and low power mode",
    "spotlight": "Find apps and files",
    "controlcenter": "Wi-Fi, sound and quick settings",
    "gnome-activities": "Overview and workspace navigation",
    "gnome-date-menu": "Calendar, notifications and media",
    "gnome-quick-settings": "Network, sound and power settings",
    "gnome-screen-record": "Recording status and stop control",
    "nowplaying": "Current tracks and playback controls",
    "sound-menu": "Audio devices and volume",
    "wifi-menu": "Quick wireless controls",
    "bluetooth-menu": "Quick device connections",
    "vpn-menu": "Quick connection switch",
    "language-menu": "Switch keyboard input layouts",
    "mirroring-menu": "Screen mirroring controls",
    "display-menu": "Brightness, appearance and night light",
    "notification-center": "Calendar and recent notifications",
    "task-view": "Window and workspace overview",
    "launcher-strip": "Open the app launcher on hover",
    "spacer": "Flexible spacing between widgets"
}
var LAYOUT_KEYS = SECTIONS.concat(["centerAnchor", "edge"])
var SNAPSHOT_LIMIT = 5

function entryId(entry) { return typeof entry === "string" ? entry : String(entry.id || "") }
function clone(value) { return JSON.parse(JSON.stringify(value)) }
function hintFor(row, armed) {
    if (armed) return "Enter again to restore · Esc cancel"
    if (!row) return ""
    if (row.type === "header") return "← → or Enter fold"
    if (row.type === "widget") return row.canToggle ? "Space toggle · 1 2 3 4 section · ← section header" : "Stays on the bar · 1 2 3 4 section"
    if (row.type === "available") return "Space switch on · 1 2 3 4 into a section"
    if (row.type === "layout") return row.slot === "mine" ? "Enter twice restore · S save" : "Enter twice restore"
    if (row.type === "icon") return "Space toggle · P pin"
    return "Space toggle"
}

function buildRows(layout, registry, collapsed, keyFor, saved, icons) {
    var rows = [], placed = new Set()
    for (var section of SECTIONS) {
        var entries = layout[section] || []
        var widgets = entries.filter(entry => !entryId(entry).startsWith("icon:"))
        rows.push({ type: "header", key: section, section, name: LABELS[section], count: widgets.length, collapsed: !!collapsed[section] })
        for (var index = 0; index < entries.length; index++) {
            var id = entryId(entries[index])
            placed.add(id)
            if (collapsed[section] || id.startsWith("icon:")) continue
            rows.push({ type: "widget", key: keyFor(section, entries[index]), id, name: WIDGET_NAMES[id] || id, section, index,
                sectionSize: entries.length, canToggle: !["tray", "taskbar", "spacer"].includes(id), canMove: id !== "tray" })
        }
    }
    var available = Object.keys(registry).filter(id => !placed.has(id)).sort()
    rows.push({ type: "header", key: "available", section: "available", name: "Available", count: available.length, collapsed: !!collapsed.available })
    if (!collapsed.available) for (var id of available)
        rows.push({ type: "available", key: "available:" + id, id, name: WIDGET_NAMES[id] || id, canToggle: true, canMove: true })
    var layouts = [{ slot: "initial", name: "Initial layout", saved: saved.initial }, { slot: "mine", name: "My layout", saved: saved.mine }]
        .concat((saved.snapshots || []).map((item, index) => ({ slot: "snapshot:" + index, name: item.name, saved: item })))
    rows.push({ type: "header", key: "layouts", section: "layouts", name: "Layouts", count: layouts.length, collapsed: !!collapsed.layouts })
    if (!collapsed.layouts) for (var item of layouts)
        rows.push({ type: "layout", key: item.slot, slot: item.slot, name: item.name, saved: item.saved })
    rows.push({ type: "header", key: "icons", section: "icons", name: "System icons", count: icons.length, collapsed: !!collapsed.icons })
    if (!collapsed.icons) {
        rows.push({ type: "icon-toggle", key: "show-icons", name: "Show system icons" })
        for (var icon of icons) rows.push({ type: "icon", key: "icon:" + icon.id, id: String(icon.id || ""), name: icon.title || icon.id, icon })
    }
    return rows
}

function snapshot(layout, name) {
    var saved = { name, savedAt: new Date().toISOString(), layout: {} }
    for (var key of LAYOUT_KEYS) if (key in layout) saved.layout[key] = clone(layout[key])
    return saved
}

function restoredLayout(current, saved) {
    var layout = clone(current)
    for (var key of LAYOUT_KEYS) {
        if (key in saved.layout) layout[key] = clone(saved.layout[key])
        else delete layout[key]
    }
    return layout
}

function parentHeader(rows, from) {
    for (var index = Math.min(from, rows.length - 1); index >= 0; index--)
        if (rows[index].type === "header") return index
    return from
}

function laneHeader(rows, from, direction) {
    for (var index = from + direction; index >= 0 && index < rows.length; index += direction)
        if (rows[index].type === "header") return index
    return from
}

function resolveKey(row, token) {
    if (["up", "k", "down", "j"].includes(token)) return { kind: "cursor", step: ["up", "k"].includes(token) ? -1 : 1 }
    if (["home", "g", "end", "G"].includes(token)) return { kind: "end", last: ["end", "G"].includes(token) }
    if (["[", "]"].includes(token)) return { kind: "lane", step: token === "[" ? -1 : 1 }
    if (!row) return { kind: "none" }
    if (["left", "h"].includes(token)) return { kind: row.type === "header" ? "fold" : "parent", collapsed: true }
    if (["right", "l"].includes(token) && row.type === "header") return { kind: "fold", collapsed: false }
    if (row.type === "header" && ["enter", "space"].includes(token)) return { kind: "fold", collapsed: !row.collapsed }
    if (["widget", "available"].includes(row.type)) {
        if (/^[1-4]$/.test(token)) return { kind: "send", section: SECTIONS[Number(token) - 1] }
        if (["space", "x"].includes(token) || row.type === "available" && token === "enter") return { kind: "toggle" }
        if (row.type === "widget") {
            if (["shift+up", "K", "shift+down", "J"].includes(token)) return { kind: "reorder", step: ["shift+up", "K"].includes(token) ? -1 : 1 }
            if (["shift+left", "H", "shift+right", "L"].includes(token)) return { kind: "send", section: SECTIONS[SECTIONS.indexOf(row.section) + (["shift+left", "H"].includes(token) ? -1 : 1)] }
        }
    }
    if (row.type === "layout" && token === "enter") return { kind: "restore" }
    if (row.type === "layout" && row.slot === "mine" && token === "s") return { kind: "save" }
    if (["icon", "icon-toggle"].includes(row.type) && ["enter", "space"].includes(token)) return { kind: "toggle" }
    if (row.type === "icon" && token === "p") return { kind: "pin" }
    return { kind: "none" }
}

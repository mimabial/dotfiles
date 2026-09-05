import QtQuick
import Quickshell

// Desktop-entry access for the dock. Omarchy's shell exposes an equivalent
// service on its shell root; this config resolves entries directly, so the dock
// owns a local one instead of reaching through `shell`.
QtObject {
    id: root

    function entryName(entry) {
        return String((entry && entry.name) || (entry && entry.id) || "")
    }

    // DesktopEntries.applications omits NoDisplay entries, so the window-only
    // org.tui.* family is unreachable through entries(). Resolve those directly.
    function lookup(appId) {
        const id = String(appId || "")
        if (!id) return null
        return DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop")
    }

    // Rows carry the entry plus its sort key, the shape DockModel expects.
    function entries() {
        const values = DesktopEntries.applications ? DesktopEntries.applications.values : []
        const rows = []
        for (let i = 0; i < values.length; i++) {
            const entry = values[i]
            if (!entry || entry.noDisplay) continue
            const name = root.entryName(entry)
            if (!name) continue
            rows.push({ entry: entry, name: name.toLowerCase() })
        }
        rows.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
        return rows
    }

    function iconSource(icon) {
        const value = String(icon || "")
        if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
        if (value.charAt(0) === "/") return "file://" + value
        const themed = Quickshell.iconPath(value, true)
        return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
    }

    // DesktopEntry.execute() is what the start menu already uses; it keeps the
    // dock off uwsm/systemd, which gtk-launch under a scope would pull back in.
    function launch(desktopId) {
        const id = String(desktopId || "")
        if (!id) return false
        const entry = DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop")
        if (!entry) return false
        entry.execute()
        return true
    }
}

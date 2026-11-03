pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property var cache: ({})

    function idsFor(toplevel) {
        const ipc = toplevel.lastIpcObject || {}
        const ids = [toplevel.wayland ? toplevel.wayland.appId : "", ipc["class"], ipc.initialClass].map(id => String(id || ""))
        return ids.filter((id, index) => id && ids.indexOf(id) === index)
    }

    function iconSource(name) {
        return name.charAt(0) === "/" ? "file://" + name : Quickshell.iconPath(name, true)
    }

    function lookup(toplevel) {
        const ids = root.idsFor(toplevel)
        const key = ids.join("|")
        if (key in root.cache) return root.cache[key]
        let entry = null
        for (let i = 0; i < ids.length && !entry; i++) entry = DesktopEntries.heuristicLookup(ids[i])
        const iconNames = entry && entry.icon ? [String(entry.icon)].concat(ids) : ids
        let icon = ""
        for (let i = 0; i < iconNames.length && !icon; i++) icon = root.iconSource(iconNames[i])
        root.cache[key] = { icon: icon, name: entry ? String(entry.name || "") : "" }
        return root.cache[key]
    }

    property Connections entriesWatch: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.cache = ({}) }
    }
}

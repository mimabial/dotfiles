.pragma library

function applications(entries) {
    const visible = []
    for (const app of entries)
        if (app && !app.noDisplay) visible.push(app)
    visible.sort((left, right) => left.name.localeCompare(right.name))
    return visible
}
function places(defaults, hiddenPaths, custom) {
    return defaults.filter(place => !hiddenPaths.includes(place.path)).concat(custom)
}
function resolvePath(value, home) {
    let path = value.replace(/^~(?=\/|$)/, home)
    if (!path.startsWith("/")) path = home + "/" + path
    return path.length > 1 ? path.replace(/\/+$/, "") : path
}
function labelIcon(label) {
    const match = label.match(/^(\S+)\s{2,}/)
    return match ? match[1] : ""
}
function labelText(label) {
    const match = label.match(/^\S+\s{2,}(.*)$/)
    return match ? match[1] : label
}
function flattenMenu(menus, menuId, prefix, output, visited) {
    const menu = menus[menuId]
    if (!menu || visited.includes(menuId)) return output
    visited.push(menuId)
    for (const item of menu.items) {
        if (!item.searchable) continue
        const path = prefix === "" ? labelText(item.label) : prefix + " › " + labelText(item.label)
        if (item.kind === "submenu") flattenMenu(menus, item.target, path, output, visited)
        else output.push({icon: labelIcon(item.label), path: path, target: item.target})
    }
    return output
}
function search(query, apps, menus, availablePlaces) {
    const needle = query.trim().toLowerCase()
    if (!needle) return []
    const matches = []
    for (const app of apps) {
        const text = (app.name + " " + app.genericName + " " + app.comment + " " + app.keywords).toLowerCase()
        if (text.includes(needle)) matches.push({type: "app", app: app})
    }
    for (const entry of flattenMenu(menus, "main", "", [], []))
        if (entry.path.toLowerCase().includes(needle)) matches.push({type: "action", entry: entry})
    for (const place of availablePlaces)
        if (place.label.toLowerCase().includes(needle)) matches.push({type: "place", place: place})
    return matches
}

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
function dropdownItems(menus, selected, menuId = "main", ancestors = []) {
    const menu = menus[menuId]
    if (!menu || ancestors.includes(menuId)) return []
    return menu.items.map(item => ({
        text: labelText(item.label), glyph: labelIcon(item.label), shortcut: item.chevron,
        checked: () => selected(item.target) ?? item.checked,
        submenu: item.kind === "submenu" ? dropdownItems(menus, selected, item.target, ancestors.concat(menuId)) : null,
        run: item.kind === "submenu" ? null : ["hyprshell", "rofi/menutree", "--action", item.target]
    }))
}
function flattenMenu(menus, menuId, prefix, output, visited) {
    const menu = menus[menuId]
    if (!menu || visited.includes(menuId)) return output
    visited.push(menuId)
    for (const item of menu.items) {
        if (!item.searchable) continue
        const label = labelText(item.label)
        const path = prefix === "" ? label : prefix + " › " + label
        if (item.kind === "submenu") flattenMenu(menus, item.target, path, output, visited)
        else output.push({icon: labelIcon(item.label), label, parent: prefix, path, target: item.target, checked: item.checked})
    }
    return output
}
function filePath(uri) {
    return uri.startsWith("file://") ? decodeURIComponent(uri.replace(/^file:\/\/(localhost)?/, "")) : uri
}
function plainText(text) {
    return text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
}
const searchGroups = {app: 0, action: 1, place: 2, file: 3}
function searchCandidate(result, title, details) {
    const name = plainText(title)
    const words = name.split(/[^a-z0-9]+/).filter(Boolean)
    return {result, name, wordStarts: " " + words.join(" "), initials: words.map(word => word[0]).join(""),
        text: name + " " + plainText(details)}
}
function fileCandidates(files) {
    return files.map(file => searchCandidate({type: "file", file}, file.text, ""))
}
function searchIndex(apps, menus, places, recentFiles) {
    return [].concat(
        apps.map(app => searchCandidate({type: "app", app}, app.name, [app.genericName, app.comment, app.keywords].join(" "))),
        flattenMenu(menus, "main", "", [], []).map(entry => searchCandidate({type: "action", entry}, entry.label, entry.parent)),
        places.map(place => searchCandidate({type: "place", place}, place.label, "")),
        fileCandidates(recentFiles))
}
function matchScore(candidate, query) {
    if (!query.split(" ").every(term => candidate.text.includes(term) || candidate.initials.includes(term))) return 0
    return candidate.name === query || candidate.name.startsWith(query + ".") ? 5
        : candidate.name.startsWith(query) ? 4
        : candidate.wordStarts.includes(" " + query) ? 3
        : candidate.name.includes(query) ? 2 : 1
}
function search(query, index, documents) {
    const needle = plainText(query.trim()).replace(/\s+/g, " ")
    if (!needle) return []
    const matches = [], paths = new Set()
    index.concat(fileCandidates(documents)).forEach((candidate, order) => {
        const score = matchScore(candidate, needle)
        const path = candidate.result.file ? filePath(candidate.result.file.uri) : null
        if (!score || paths.has(path)) return
        if (path) paths.add(path)
        matches.push({candidate, score, order})
    })
    return matches
        .sort((a, b) => searchGroups[a.candidate.result.type] - searchGroups[b.candidate.result.type]
            || b.score - a.score || a.order - b.order)
        .map(match => Object.assign({score: match.score}, match.candidate.result))
}

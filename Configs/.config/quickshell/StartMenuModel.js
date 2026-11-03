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
    return text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
}
const searchGroups = {window: 0, app: 1, action: 2, place: 3, file: 4}
const queryFilters = {a: "app", w: "window", f: "file"}
function parseQuery(text) {
    const filtered = text.trim().match(/^([a-z]):\s*(.*)$/i)
    const type = filtered ? queryFilters[filtered[1].toLowerCase()] : undefined
    return type ? {text: filtered[2], type} : {text: text.trim(), type: ""}
}
function searchNeedle(text) {
    return plainText(text.trim()).replace(/\s+/g, " ")
}
function calculatorExpression(query) {
    if (query.type) return ""
    const forced = query.text.match(/^=\s*(\S.*)$/)
    if (forced) return forced[1]
    return /^[-(.\d]/.test(query.text) && /.[-+*\/^%×÷]|\sto\s/i.test(query.text) ? query.text : ""
}
const webEngines = {
    aw: {name: "Arch Wiki", icon: "\u{f08c7}", url: "https://wiki.archlinux.org/index.php?search="},
    aur: {name: "AUR", icon: "\u{f08c7}", url: "https://aur.archlinux.org/packages?K="},
    gh: {name: "GitHub", icon: "\u{f02a4}", url: "https://github.com/search?q="},
    mdn: {name: "MDN", icon: "\u{f059f}", url: "https://developer.mozilla.org/en-US/search?q="},
    w: {name: "Wikipedia", icon: "\u{f05ac}", url: "https://en.wikipedia.org/w/index.php?search="},
    yt: {name: "YouTube", icon: "\u{f05c3}", url: "https://www.youtube.com/results?search_query="}
}
const defaultWebEngine = {name: "the web", icon: "\u{f059f}", url: "https://duckduckgo.com/?q="}
function webSearch(text) {
    const words = text.match(/^(\S+)\s+(\S.*)$/)
    const engineName = words ? words[1].toLowerCase() : ""
    const explicitEngine = webEngines.hasOwnProperty(engineName)
    const engine = explicitEngine ? webEngines[engineName] : defaultWebEngine
    const query = explicitEngine ? words[2] : text
    return {type: "webSearch", explicitEngine, engine, query, url: engine.url + encodeURIComponent(query)}
}
function resultKey(result) {
    switch (result.type) {
    case "app": return "app:" + result.app.id
    case "window": return result.window.entryId ? "app:" + result.window.entryId : "window:" + result.window.appId
    case "action": return "action:" + result.entry.target
    case "place": return "place:" + result.place.path
    case "file": return "file:" + filePath(result.file.uri)
    }
    return ""
}
function searchCandidate(result, title, details) {
    const name = plainText(title)
    const words = name.split(/[^a-z0-9]+/).filter(Boolean)
    return {result, key: resultKey(result), name, wordStarts: " " + words.join(" "), initials: words.map(word => word[0]).join(""),
        text: name + " " + plainText(details)}
}
function fileCandidates(files) {
    return files.map(file => searchCandidate({type: "file", file}, file.text, ""))
}
function searchIndex(apps, menus, places, recentFiles, windows) {
    return [].concat(
        apps.map(app => searchCandidate({type: "app", app}, app.name, [app.genericName, app.comment, app.keywords].join(" "))),
        windows.map(window => searchCandidate({type: "window", window}, window.name, window.title)),
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
const hourMs = 3600000, dayMs = 24 * hourMs
const recencyWeights = [[hourMs, 4], [dayMs, 2], [7 * dayMs, 0.5], [90 * dayMs, 0.25], [Infinity, 0.1]]
const halfBonusRank = 2
const itemBonusLimit = 0.5
const queryBonusLimit = 1
const itemUseLimit = 256
const queryUseLimit = 512
function useRank(use, now) {
    return use ? use.count * recencyWeights.find(([age]) => now - use.last < age)[1] : 0
}
function saturated(rank) {
    return rank / (rank + halfBonusRank)
}
function queryUseKey(needle, key) {
    return needle + "\n" + key
}
function learnedBonus(usage, key, needle, now) {
    return itemBonusLimit * saturated(useRank(usage.items[key], now))
        + queryBonusLimit * saturated(useRank(usage.queries[queryUseKey(needle, key)], now))
}
function newestUses(uses, limit) {
    const kept = {}
    for (const key of Object.keys(uses).sort((a, b) => uses[b].last - uses[a].last).slice(0, limit)) kept[key] = uses[key]
    return kept
}
function recordUse(usage, key, needle, now) {
    const counted = use => ({count: (use ? use.count : 0) + 1, last: now})
    const items = Object.assign({}, usage.items), queries = Object.assign({}, usage.queries)
    items[key] = counted(items[key])
    for (let end = 1; end <= needle.length; end++) {
        if (needle[end - 1] === " ") continue
        const pair = queryUseKey(needle.slice(0, end), key)
        queries[pair] = counted(queries[pair])
    }
    return {items: newestUses(items, itemUseLimit), queries: newestUses(queries, queryUseLimit)}
}
function ordered(matches) {
    const groupBest = {}
    for (const match of matches) groupBest[match.result.type] = Math.max(groupBest[match.result.type] ?? 0, match.score)
    return matches
        .sort((a, b) => groupBest[b.result.type] - groupBest[a.result.type]
            || searchGroups[a.result.type] - searchGroups[b.result.type] || b.score - a.score || a.order - b.order)
        .map(match => match.result)
}
function search(query, index, documents, usage, now) {
    const needle = searchNeedle(query.text)
    if (!needle && !query.type) return []
    const matches = [], paths = new Set()
    index.concat(fileCandidates(documents)).forEach((candidate, order) => {
        if (query.type && candidate.result.type !== query.type) return
        const score = matchScore(candidate, needle)
        const path = candidate.result.file ? filePath(candidate.result.file.uri) : null
        if (!score || paths.has(path)) return
        if (path) paths.add(path)
        matches.push({result: candidate.result, score: usage ? score + learnedBonus(usage, candidate.key, needle, now) : score, order})
    })
    return ordered(matches)
}
function frequent(index, usage, now, limit) {
    return ordered(index
        .map((candidate, order) => ({result: candidate.result, score: useRank(usage.items[candidate.key], now), order}))
        .filter(match => match.score > 0)
        .sort((a, b) => b.score - a.score || a.order - b.order)
        .slice(0, limit))
}

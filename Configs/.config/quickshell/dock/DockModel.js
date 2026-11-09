
var IGNORED_TOKENS = {
  "org": true, "com": true, "io": true, "net": true, "app": true, "apps": true, "bin": true,
  "linux": true, "desktop": true, "client": true, "gui": true, "wrapper": true, "launcher": true,
  "window": true, "default": true, "profile": true, "profile_1": true, "profile_2": true,
  "chrome": true, "chromium": true, "brave": true, "edge": true, "microsoft-edge": true,
  "helium": true, "helium-browser": true, "opera": true, "vivaldi": true,
  "web": true, "steam": true,
  "https": true, "http": true, "www": true, "x86_64": true, "x86": true, "amd64": true, "lib": true
};
var NOISE_AFFIX = "app|bin|linux|gtk|wrapper|desktop|client|qt\\d?|gui"
var NOISE_WORD = new RegExp("^(?:" + NOISE_AFFIX + ")$")
var WEB_APP_HOST = /^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(?:https?_+)?(?:www\.)?([^_]+\.[^_]+)/

function stripDesktop(id) {
  var value = String(id == null ? "" : id).trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function toArray(list) {
  if (Array.isArray(list)) return list
  if (list && typeof list.length === "number") {
    var out = []
    for (var i = 0; i < list.length; i++) out.push(list[i])
    return out
  }
  return []
}

function normalizeId(id) {
  return stripDesktop(id)
}

function copyMap(src) {
  var out = {}
  for (var key in src) out[key] = src[key]
  return out
}

function workspaceShort(wsId, wsName) {
  if (wsId === null || wsId === undefined || wsId < 0) return ""
  var name = String(wsName == null ? "" : wsName)
  if (name && name.length <= 2) return name
  return String(wsId)
}

function getCandidates(id) {
  var raw = stripDesktop(id).toLowerCase()
  if (!raw) return []
  var list = [raw]

  var webAppMatch = raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                 || raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
  if (webAppMatch) {
    var webTarget = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
    if (webTarget && list.indexOf(webTarget) < 0) list.push(webTarget)
    var webDomain = webTarget.split(/[\.\/_]+/)
    for (var segment of webDomain) {
      if (segment && list.indexOf(segment) < 0) list.push(segment)
    }
  }

  var parts = raw.split(/[\.\/_-]+/)
  for (var part of parts) {
    if (part && list.indexOf(part) < 0) list.push(part)
  }

  var len = list.length
  for (var i = 0; i < len; i++) {
    var item = list[i]
    var stripped = item.replace(new RegExp("[-_](?:" + NOISE_AFFIX + ")$", "i"), "")
    if (stripped && list.indexOf(stripped) < 0) list.push(stripped)
    var prefixStripped = item.replace(new RegExp("^(?:" + NOISE_AFFIX + ")[-_]", "i"), "")
    if (prefixStripped && list.indexOf(prefixStripped) < 0) list.push(prefixStripped)
  }

  var out = []
  for (var token of list) {
    if (token && !IGNORED_TOKENS[token] && out.indexOf(token) < 0) {
      out.push(token)
    }
  }
  return out
}

function identityWords(name) {
  return name.split(/[\s._\/-]+/).filter(function (word) { return word && !NOISE_WORD.test(word) })
}

function appName(raw) {
  var web = raw.match(WEB_APP_HOST)
  if (web) return web[1].slice(0, web[1].lastIndexOf("."))
  var labels = raw.split(".")
  if (labels.length < 3) return raw
  var named = labels.filter(function (label) { return identityWords(label).length > 0 })
  return named.length > 0 ? named[named.length - 1] : raw
}

function appIdentity(id) {
  return identityWords(appName(stripDesktop(id).toLowerCase())).sort().join(" ")
}

function isAppMatch(idA, idB) {
  if (!idA || !idB) return false
  var a = stripDesktop(idA).toLowerCase()
  var b = stripDesktop(idB).toLowerCase()
  if (a === b) return true
  var identity = appIdentity(a)
  return identity !== "" && identity === appIdentity(b)
}

function parsePinned(raw) {
  var text = String(raw == null ? "" : raw).trim()
  if (!text) return []

  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return []

  var arr = Array.isArray(parsed.pinned) ? parsed.pinned : []
  var out = []
  var seen = {}
  for (var appId of arr) {
    var id = stripDesktop(appId)
    if (!id || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function serializePinned(pinnedIds) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds : []
  var cleaned = []
  var seen = {}
  for (var appId of arr) {
    var id = stripDesktop(appId)
    if (!id || seen[id]) continue
    seen[id] = true
    cleaned.push(id)
  }
  return JSON.stringify({ pinned: cleaned }, null, 2)
}

function togglePinned(pinnedIds, appId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds.slice() : []
  var id = stripDesktop(appId)
  if (!id) return arr
  var idx = arr.indexOf(id)
  if (idx >= 0) arr.splice(idx, 1)
  else arr.push(id)
  return arr
}

function isPinned(pinnedIds, appId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds : []
  return arr.indexOf(stripDesktop(appId)) >= 0
}

function reorderPinned(pinnedIds, appId, insertBeforeId) {
  var arr = Array.isArray(pinnedIds) ? pinnedIds.slice() : []
  var id = stripDesktop(appId)
  if (!id) return arr
  if (insertBeforeId && stripDesktop(insertBeforeId) === id) return arr

  var fromIdx = arr.indexOf(id)
  if (fromIdx < 0) return arr

  arr.splice(fromIdx, 1)

  if (!insertBeforeId) {
    arr.push(id)
  } else {
    var toIdx = arr.indexOf(stripDesktop(insertBeforeId))
    if (toIdx < 0) arr.push(id)
    else arr.splice(toIdx, 0, id)
  }
  return arr
}

function exactEntryFor(appRows, appId) {
  var want = stripDesktop(appId).toLowerCase()
  if (!want || !appRows) return null
  for (var appRow of appRows) {
    var entry = appRow && appRow.entry
    if (entry && stripDesktop(entry.id).toLowerCase() === want) return entry
  }
  return null
}

function entryFor(appRows, appId) {
  var exact = exactEntryFor(appRows, appId)
  if (exact) return exact
  var want = stripDesktop(appId)
  if (!want || !appRows) return null

  var identity = appIdentity(want)
  if (identity !== "") {
    for (var appRow of appRows) {
      var entry = appRow && appRow.entry
      if (entry && (appIdentity(entry.id) === identity || appIdentity(entry.name || "") === identity)) return entry
    }
  }

  var desktopIdCandidates = getCandidates(want)

  for (var appRow of appRows) {
    var entry = appRow && appRow.entry
    if (!entry) continue
    var execStr = String(entry.exec || "").toLowerCase()
    if (execStr && (execStr.indexOf("http://") >= 0 || execStr.indexOf("https://") >= 0 || execStr.indexOf("--app") >= 0)) {
      for (var candidate of desktopIdCandidates) {
        if (candidate.length >= 4 && !IGNORED_TOKENS[candidate] && execStr.indexOf(candidate) >= 0) return entry
      }
    }
  }

  for (var appRow of appRows) {
    var entry = appRow && appRow.entry
    if (!entry) continue
    var generic = String(entry.genericName || "").toLowerCase()
    if (generic && desktopIdCandidates.indexOf(generic) >= 0) return entry
  }

  return null
}

function hyprAddress(raw) {
  var value = String(raw || "").trim()
  if (value.slice(0, 2) === "0x" || value.slice(0, 2) === "0X") value = value.slice(2)
  return value ? "0x" + value : ""
}

function windowAddress(handle) {
  return hyprAddress(handle && handle.address)
}

function luaString(value) {
  return String(value == null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

function windowByAddress(windows, address, isParked) {
  if (!address) return null
  for (var window of windows) {
    if (window && window.address === address) return isParked(window) ? null : window
  }
  return null
}

function windowsByParkedState(windows, isParked, parked) {
  var result = []
  for (var i = 0; i < windows.length; i++)
    if (windows[i] && isParked(windows[i]) === parked) result.push(windows[i])
  return result
}

function focusedIndex(windows, activeAddress) {
  if (!activeAddress) return -1
  for (var i = 0; i < windows.length; i++)
    if (windows[i] && windows[i].address === activeAddress) return i
  return -1
}

function windowOnWorkspace(windows, workspaceOf, workspaceId, workspaceName) {
  for (var window of windows) {
    var workspace = workspaceOf(window)
    if (window && (workspace === String(workspaceId) || workspace === workspaceName)) return window
  }
  return null
}

function stepWindow(windows, direction, activeAddress) {
  if (windows.length < 2) return windows[0] || null
  var step = direction < 0 ? -1 : 1, at = focusedIndex(windows, activeAddress)
  return at < 0 ? windows[step > 0 ? 0 : windows.length - 1]
    : windows[(at + step + windows.length) % windows.length]
}

function oldestWindow(windows, timestamps) {
  if (windows.length < 2) return windows[0] || null
  var oldest = windows[0], oldestAt = timestamps[oldest.address] || 0
  for (var i = 1; i < windows.length; i++) {
    var parkedAt = timestamps[windows[i].address] || 0
    if (parkedAt < oldestAt) {
      oldest = windows[i]
      oldestAt = parkedAt
    }
  }
  return oldest
}

function workspaceLabel(name) {
  var value = String(name || "")
  if (value.indexOf("special:") !== 0) return value
  var suffix = value.slice(8)
  return suffix ? suffix.charAt(0).toUpperCase() : ""
}

var MINIMIZED_WORKSPACE = "special:minimized"

function isMinimizedWorkspace(name) {
  var value = String(name || "")
  return value === MINIMIZED_WORKSPACE || value.indexOf(MINIMIZED_WORKSPACE + "-") === 0
}

function windowsByApp(toplevels, hyprFor, minimizedOrigins) {
  var origins = minimizedOrigins || {}
  var grouped = { appIds: [], windowsById: {} }
  for (var toplevel of toArray(toplevels)) {
    if (!toplevel) continue
    var appId = stripDesktop(toplevel.appId)
    if (!appId) continue
    if (!grouped.windowsById[appId]) {
      grouped.windowsById[appId] = []
      grouped.appIds.push(appId)
    }
    var handle = hyprFor ? hyprFor(toplevel) : null
    var address = windowAddress(handle)
    var workspace = handle ? handle.workspace : null
    var workspaceName = workspace ? String(workspace.name || workspace.id || "") : ""
    grouped.windowsById[appId].push({
      title: String(toplevel.title || "Window"),
      address: address,
      appId: appId,
      workspaceName: workspaceName,
      isMinimized: isMinimizedWorkspace(workspaceName) || Boolean(address && origins[address])
    })
  }
  return grouped
}

function windowsMatchingApp(grouped, appId) {
  if (grouped.windowsById[appId] && grouped.windowsById[appId].length > 0) return grouped.windowsById[appId]
  for (var runningId of grouped.appIds) {
    if (isAppMatch(appId, runningId)) return grouped.windowsById[runningId] || []
  }
  return []
}

function addNamesAndIcons(entries, appRows, appLibrary) {
  for (var item of entries) {
    var entry = (appLibrary && appLibrary.lookup) ? appLibrary.lookup(item.appId) : null
    if (!entry) entry = entryFor(appRows, item.appId)
    if (entry && appLibrary) {
      item.name = appLibrary.entryName(entry)
      item.icon = appLibrary.iconSource(entry.icon)
    } else {
      item.name = item.appId
      var iconFound = ""
      if (appLibrary) {
        for (var candidate of getCandidates(item.appId)) {
          var testSrc = appLibrary.iconSource(candidate)
          if (testSrc && testSrc.indexOf("application-x-executable") < 0) {
            iconFound = testSrc
            break
          }
        }
      }
      item.icon = iconFound
    }
  }
}

function dockEntry(appId, pinned, windows) {
  return { id: appId, appId: appId, pinned: pinned, running: windows.length > 0, windows: windows.length, windowList: windows }
}

function matchesPinnedApp(pinned, appId) {
  return pinned.some(function (pinnedId) { return isAppMatch(pinnedId, appId) })
}

function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor, minimizedOrigins, recentIds, recentLimit) {
  var pinned = Array.isArray(pinnedIds) ? pinnedIds : []
  var grouped = windowsByApp(toplevels, hyprFor, minimizedOrigins)
  var seen = {}

  var pinnedOut = []
  for (var pinnedId of pinned) {
    var id = stripDesktop(pinnedId)
    if (!id || seen[id]) continue
    seen[id] = true
    pinnedOut.push(dockEntry(id, true, windowsMatchingApp(grouped, id)))
  }
  addNamesAndIcons(pinnedOut, appRows, appLibrary)

  var runningOut = []
  for (var runningId of grouped.appIds) {
    if (matchesPinnedApp(pinned, runningId) || seen[runningId]) continue
    seen[runningId] = true
    runningOut.push(dockEntry(runningId, false, grouped.windowsById[runningId]))
  }
  var recents = toArray(recentIds)
  var recentOut = []
  for (var j = 0; j < recents.length && recentOut.length < recentLimit; j++) {
    var recentId = stripDesktop(recents[j])
    if (!recentId || seen[recentId] || matchesPinnedApp(pinned, recentId)) continue
    seen[recentId] = true
    recentOut.push(dockEntry(recentId, false, []))
  }
  runningOut = runningOut.concat(recentOut)
  addNamesAndIcons(runningOut, appRows, appLibrary)

  return { pinned: pinnedOut, running: runningOut }
}

function allWindowsMinimized(windowList, resolveLiveWorkspace) {
  var list = toArray(windowList)
  if (list.length === 0) return false
  for (var window of list) {
    if (!window) return false
    if (window.isMinimized) continue
    var ws = resolveLiveWorkspace ? String(resolveLiveWorkspace(window) || "") : String(window.workspaceName || "")
    if (!isMinimizedWorkspace(ws)) return false
  }
  return true
}

function pickAppWindow(toplevels, activeToplevel, appId, direction) {
  var want = stripDesktop(appId)
  if (!want) return null
  var list = toArray(toplevels)
  var matching = []

  for (var toplevel of list) {
    if (toplevel && (stripDesktop(toplevel.appId) === want || isAppMatch(toplevel.appId, want))) matching.push(toplevel)
  }

  if (matching.length === 0) return null
  if (matching.length === 1) return matching[0]

  var dir = (typeof direction === "number" && direction < 0) ? -1 : 1
  var focusedWindowIndex = -1
  for (var j = 0; j < matching.length; j++) {
    if (matching[j] === activeToplevel || matching[j].activated) {
      focusedWindowIndex = j
      break
    }
  }

  if (focusedWindowIndex < 0) return matching[dir > 0 ? 0 : matching.length - 1]
  return matching[(focusedWindowIndex + dir + matching.length) % matching.length]
}

function focusWindow(toplevel) {
  if (toplevel && toplevel.activate) toplevel.activate()
}

function closeApp(toplevels, appId) {
  var want = stripDesktop(appId)
  if (!want) return 0
  var list = toArray(toplevels)
  var closed = 0
  for (var toplevel of list) {
    if (!toplevel) continue
    if (stripDesktop(toplevel.appId) === want || isAppMatch(toplevel.appId, want)) {
      if (toplevel.close) toplevel.close()
      closed += 1
    }
  }
  return closed
}

function folderIconFor(path, explicitIcon) {
  if (explicitIcon) return explicitIcon
  var norm = String(path || "").toLowerCase()
  if (norm.indexOf("download") >= 0) return "folder-download"
  if (norm.indexOf("document") >= 0) return "folder-documents"
  if (norm.indexOf("picture") >= 0) return "folder-pictures"
  if (norm.indexOf("music") >= 0) return "folder-music"
  if (norm.indexOf("video") >= 0) return "folder-videos"
  if (norm === "~" || (norm.indexOf("/home/") === 0 && norm.split("/").length <= 3)) return "user-home"
  return "folder"
}

function resolveThemedFolderIcon(iconName) {
  var name = String(iconName || "folder").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  var placeAliases = {
    "folder-development": "folder",
    "folder-projects": "folder",
    "folder-code": "folder",
    "folder-git": "folder",
    "folder-github": "folder",
    "folder-src": "folder",
    "folder-source": "folder",
    "folder-build": "folder"
  }
  if (placeAliases[name]) name = placeAliases[name]

  var validPlaces = [
    "folder", "folder-documents", "folder-download", "folder-music",
    "folder-pictures", "folder-publicshare", "folder-remote",
    "folder-templates", "folder-videos", "user-home", "user-desktop", "user-trash", "user-trash-full"
  ]
  return validPlaces.indexOf(name) >= 0 ? name : "folder"
}

function isPlaceIcon(name) {
  return name === "folder" || name.indexOf("folder-") === 0 || name === "user-home"
}

function resolveFileItemIcon(iconName) {
  var name = String(iconName || "text-x-generic").trim()
  return isPlaceIcon(name) ? resolveThemedFolderIcon(name) : name
}

function playingAppIds(players, toplevels) {
  var windows = toArray(toplevels)
  return toArray(players).map(function (player) {
    var track = String(player.trackTitle || "")
    var owner = track === "" ? null : windows.find(function (toplevel) { return String(toplevel.title || "").indexOf(track) >= 0 })
    return owner ? stripDesktop(owner.appId) : String(player.desktopEntry || player.identity || "")
  })
}

var FILE_ICON_SUFFIXES = {
  "image-x-generic": ["png", "jpg", "jpeg", "webp", "svg", "gif"],
  "video-x-generic": ["mp4", "mkv", "webm", "mov", "avi"],
  "audio-x-generic": ["mp3", "flac", "wav", "ogg", "m4a"],
  "package-x-generic": ["zip", "tar", "gz", "xz", "7z", "rar"],
  "application-pdf": ["pdf"],
  "text-x-generic": ["txt", "md", "json", "qml", "py", "cpp", "js", "lua", "rs", "go", "html", "css"]
}

function fileIcon(suffix, isDir) {
  if (isDir) return "folder"
  var wanted = String(suffix || "").toLowerCase()
  for (var icon in FILE_ICON_SUFFIXES)
    if (FILE_ICON_SUFFIXES[icon].indexOf(wanted) >= 0) return icon
  return "application-x-executable"
}

function sizeLabel(bytes) {
  var units = ["B", "KB", "MB", "GB"]
  var size = Number(bytes) || 0
  var unit = 0
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024
    unit++
  }
  return unit === 0 ? size + " B" : size.toFixed(1) + " " + units[unit]
}

function fileUrl(path) {
  return "file://" + String(path || "").split("/").map(encodeURIComponent).join("/")
}

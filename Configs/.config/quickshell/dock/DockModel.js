
var IGNORED_TOKENS = {
  "org": true, "com": true, "io": true, "net": true, "app": true, "apps": true, "bin": true,
  "linux": true, "desktop": true, "client": true, "gui": true, "wrapper": true, "launcher": true,
  "window": true, "default": true, "profile": true, "profile_1": true, "profile_2": true,
  "chrome": true, "chromium": true, "brave": true, "edge": true, "microsoft-edge": true,
  "helium": true, "helium-browser": true, "opera": true, "vivaldi": true,
  "web": true, "steam": true,
  "https": true, "http": true, "www": true, "x86_64": true, "x86": true, "amd64": true, "lib": true
};

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
    var stripped = item.replace(/[-_](app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)$/i, "")
    if (stripped && list.indexOf(stripped) < 0) list.push(stripped)
    var prefixStripped = item.replace(/^(app|bin|linux|gtk|wrapper|desktop|client|qt\d?|gui)[-_]/i, "")
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

function isAppMatch(idA, idB) {
  if (!idA || !idB) return false
  var a = stripDesktop(idA).toLowerCase()
  var b = stripDesktop(idB).toLowerCase()
  if (a === b) return true

  var candidatesA = getCandidates(a)
  var candidatesB = getCandidates(b)
  for (var candidate of candidatesA) {
    if (candidatesB.indexOf(candidate) >= 0) return true
  }
  return false
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

  var desktopIdCandidates = getCandidates(want)
  for (var appRow of appRows) {
    var entry = appRow && appRow.entry
    if (!entry) continue
    var entryCandidates = getCandidates(entry.id)
      .concat(getCandidates(entry.name))
      .concat(getCandidates(entry.icon))
    for (var candidate of desktopIdCandidates) {
      if (entryCandidates.indexOf(candidate) >= 0) return entry
    }
  }

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

function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor, isMinimizedWs, minimizedOrigins, appGroups, recentIds, recentLimit) {
  var pinned = Array.isArray(pinnedIds) ? pinnedIds : []
  var list = toArray(toplevels)
  var isParkedWorkspace = typeof isMinimizedWs === "function"
    ? isMinimizedWs
    : function (name) { return name === "special:minimized" }
  var minOrigins = minimizedOrigins || {}
  var groupedIds = []
  var groups = toArray(appGroups)
  for (var group of groups) {
    var apps = toArray(group && group.apps)
    for (var app of apps) {
      var groupedId = stripDesktop(app)
      if (groupedId && groupedIds.indexOf(groupedId) < 0) groupedIds.push(groupedId)
    }
  }

  function isGrouped(appId) {
    for (var i = 0; i < groupedIds.length; i++)
      if (isAppMatch(appId, groupedIds[i])) return true
    return false
  }

  function isPinnedApp(appId) {
    for (var i = 0; i < pinned.length; i++)
      if (isAppMatch(pinned[i], appId)) return true
    return false
  }

  var runningIds = []
  var winMap = {}
  for (var toplevel of list) {
    if (!toplevel) continue
    var appId = stripDesktop(toplevel.appId)
    if (!appId) continue
    if (!winMap[appId]) {
      winMap[appId] = []
      runningIds.push(appId)
    }
    var h = hyprFor ? hyprFor(toplevel) : null
    var addr = windowAddress(h)
    var ws = h ? h.workspace : null
    var wsName = ws ? String(ws.name || ws.id || "") : ""
    var isParked = (wsName !== "" && isParkedWorkspace(wsName)) || Boolean(addr && minOrigins[addr])
    winMap[appId].push({
      title: String(toplevel.title || "Window"),
      address: addr,
      appId: appId,
      workspaceName: wsName,
      isMinimized: isParked
    })
  }

  function getWindowsFor(targetId) {
    if (winMap[targetId] && winMap[targetId].length > 0) return winMap[targetId]
    for (var runningId of runningIds) {
      if (isAppMatch(targetId, runningId)) {
        return winMap[runningId] || []
      }
    }
    return []
  }

  function enrich(list) {
    for (var item of list) {
      var entry = (appLibrary && appLibrary.lookup) ? appLibrary.lookup(item.appId) : null
      if (!entry) entry = entryFor(appRows, item.appId)
      if (entry && appLibrary) {
        item.name = appLibrary.entryName(entry)
        item.icon = appLibrary.iconSource(entry.icon)
      } else {
        item.name = item.appId
        var iconFound = ""
        if (appLibrary) {
          var candidates = getCandidates(item.appId)
          for (var candidate of candidates) {
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

  var pinnedOut = []
  var seen = {}
  var j = 0

  for (j = 0; j < pinned.length; j++) {
    var pid = stripDesktop(pinned[j])
    if (!pid || seen[pid] || isGrouped(pid)) continue
    seen[pid] = true
    var wins = getWindowsFor(pid)
    pinnedOut.push({
      id: pid,
      appId: pid,
      pinned: true,
      running: wins.length > 0,
      windows: wins.length,
      windowList: wins
    })
  }
  enrich(pinnedOut)

  var runningOut = []
  for (j = 0; j < runningIds.length; j++) {
    var rid = runningIds[j]
    if (isPinnedApp(rid) || isGrouped(rid) || seen[rid]) continue
    seen[rid] = true
    var wins = winMap[rid] || []
    runningOut.push({
      id: rid,
      appId: rid,
      pinned: false,
      running: true,
      windows: wins.length,
      windowList: wins
    })
  }
  var recentOut = []
  var recents = toArray(recentIds)
  for (j = 0; j < recents.length && recentOut.length < recentLimit; j++) {
    var cid = stripDesktop(recents[j])
    if (!cid || seen[cid] || isPinnedApp(cid) || isGrouped(cid)) continue
    seen[cid] = true
    recentOut.push({ id: cid, appId: cid, pinned: false, running: false, windows: 0, windowList: [] })
  }
  runningOut = runningOut.concat(recentOut)
  enrich(runningOut)

  var groupedOut = []
  for (j = 0; j < groupedIds.length; j++) {
    var gid = groupedIds[j]
    var groupedWindows = getWindowsFor(gid)
    if (groupedWindows.length > 0) groupedOut.push({
      id: gid,
      appId: gid,
      pinned: false,
      running: true,
      windows: groupedWindows.length,
      windowList: groupedWindows
    })
  }
  enrich(groupedOut)

  return { pinned: pinnedOut, running: runningOut, grouped: groupedOut }
}

function allWindowsMinimized(windowList, resolveLiveWorkspace, isMinimizedWs) {
  var isParkedWorkspace = typeof isMinimizedWs === "function"
    ? isMinimizedWs
    : function (name) { return name === "special:minimized" }
  var list = toArray(windowList)
  if (list.length === 0) return false
  for (var window of list) {
    if (!window) return false
    if (window.isMinimized) continue
    var ws = resolveLiveWorkspace ? String(resolveLiveWorkspace(window) || "") : String(window.workspaceName || "")
    if (!isParkedWorkspace(ws)) return false
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

// Pure helpers for the dock plugin. No QML state — the host object owns the
// model; this file only turns inputs into output arrays.

var IGNORED_TOKENS = {
  "org": true, "com": true, "io": true, "net": true, "app": true, "apps": true, "bin": true,
  "linux": true, "desktop": true, "client": true, "gui": true, "wrapper": true, "launcher": true,
  "window": true, "default": true, "profile": true, "profile_1": true, "profile_2": true,
  "chrome": true, "chromium": true, "brave": true, "edge": true, "microsoft-edge": true,
  "helium": true, "helium-browser": true, "opera": true, "vivaldi": true,
  "web": true,
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

// Compact workspace label for a tooltip: numbered workspaces only. Special
// workspaces have no number worth showing, so they get nothing.
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

  // WebApp extraction (Chrome, Chromium, Brave, Edge, Helium, Opera, Vivaldi PWAs)
  var webAppMatch = raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)__?-(?:default|profile.*)$/i)
                 || raw.match(/^(?:chrome|chromium|brave|edge|microsoft-edge|helium|helium-browser|opera|vivaldi)-(.*?)$/i)
  if (webAppMatch) {
    var webTarget = webAppMatch[1].replace(/^https?___?/i, "").replace(/__.*$/, "")
    if (webTarget && list.indexOf(webTarget) < 0) list.push(webTarget)
    var webDomain = webTarget.split(/[\.\/_]+/)
    for (var w = 0; w < webDomain.length; w++) {
      var seg = webDomain[w]
      if (seg && list.indexOf(seg) < 0) list.push(seg)
    }
  }

  // Split by dots, underscores, dashes, slashes
  var parts = raw.split(/[\.\/_-]+/)
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i]
    if (p && list.indexOf(p) < 0) list.push(p)
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
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (s && !IGNORED_TOKENS[s] && out.indexOf(s) < 0) {
      out.push(s)
    }
  }
  return out
}

function isAppMatch(idA, idB) {
  if (!idA || !idB) return false
  var a = stripDesktop(idA).toLowerCase()
  var b = stripDesktop(idB).toLowerCase()
  if (a === b) return true

  var candsA = getCandidates(a)
  var candsB = getCandidates(b)
  for (var i = 0; i < candsA.length; i++) {
    var ca = candsA[i]
    if (candsB.indexOf(ca) >= 0) return true
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
  for (var i = 0; i < arr.length; i++) {
    var id = stripDesktop(arr[i])
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
  for (var i = 0; i < arr.length; i++) {
    var id = stripDesktop(arr[i])
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

// Reorder pinned apps: move appId from its current position to insertBeforeId.
// If insertBeforeId is null/empty, move to the end. Dropping onto the dragged
// item itself is a no-op (prevents the "teleport to end" self-drop bug).
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

function entryFor(appRows, appId) {
  var want = stripDesktop(appId)
  if (!want || !appRows) return null
  var wantLower = want.toLowerCase()

  for (var i = 0; i < appRows.length; i++) {
    var row = appRows[i]
    var entry = row && row.entry
    if (!entry) continue
    if (stripDesktop(entry.id) === want || stripDesktop(entry.id).toLowerCase() === wantLower) return entry
  }

  // Candidate tokens bridge webapp/profile suffixes and desktop IDs.
  var wantCands = getCandidates(want)
  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var entryCands = getCandidates(entry.id)
      .concat(getCandidates(entry.name))
      .concat(getCandidates(entry.icon))
    for (var k = 0; k < wantCands.length; k++) {
      var cand = wantCands[k]
      if (entryCands.indexOf(cand) >= 0) return entry
    }
  }

  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var execStr = String(entry.exec || "").toLowerCase()
    if (execStr && (execStr.indexOf("http://") >= 0 || execStr.indexOf("https://") >= 0 || execStr.indexOf("--app") >= 0)) {
      for (var k = 0; k < wantCands.length; k++) {
        var cand = wantCands[k]
        if (cand.length >= 4 && !IGNORED_TOKENS[cand] && execStr.indexOf(cand) >= 0) return entry
      }
    }
  }

  for (var i = 0; i < appRows.length; i++) {
    var entry = appRows[i] && appRows[i].entry
    if (!entry) continue
    var generic = String(entry.genericName || "").toLowerCase()
    if (generic && wantCands.indexOf(generic) >= 0) return entry
  }

  return null
}

function windowAddress(handle) {
  var value = String((handle && handle.address) || "").trim()
  if (!value) return ""
  if (value.slice(0, 2) === "0x" || value.slice(0, 2) === "0X") value = value.slice(2)
  return "0x" + value
}

// isMinimizedWs: predicate over a workspace name. Each parked window gets its
// own special workspace, so there is no single name to compare against.
function buildEntries(pinnedIds, toplevels, appRows, appLibrary, hyprFor, isMinimizedWs, minimizedOrigins) {
  var pinned = Array.isArray(pinnedIds) ? pinnedIds : []
  var list = toArray(toplevels)
  var isMinWs = typeof isMinimizedWs === "function"
    ? isMinimizedWs
    : function (name) { return name === "special:minimized" }
  var minOrigins = minimizedOrigins || {}

  var runningIds = []
  var winMap = {}
  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
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
    // With no handle yet, the origins map is the only evidence; the name stays
    // empty and isMinimized carries the state.
    var isParked = (wsName !== "" && isMinWs(wsName)) || Boolean(addr && minOrigins[addr])
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
    for (var k = 0; k < runningIds.length; k++) {
      var rid = runningIds[k]
      if (isAppMatch(targetId, rid)) {
        return winMap[rid] || []
      }
    }
    return []
  }

  function enrich(list) {
    for (var j = 0; j < list.length; j++) {
      var item = list[j]
      // An exact desktop id wins over entryFor's token matching, and is the only
      // way to reach the NoDisplay entries appRows leaves out.
      var entry = (appLibrary && appLibrary.lookup) ? appLibrary.lookup(item.appId) : null
      if (!entry) entry = entryFor(appRows, item.appId)
      if (entry && appLibrary) {
        item.name = appLibrary.entryName(entry)
        item.icon = appLibrary.iconSource(entry.icon)
      } else {
        item.name = item.appId
        var iconFound = ""
        if (appLibrary) {
          var cands = getCandidates(item.appId)
          for (var k = 0; k < cands.length; k++) {
            var cand = cands[k]
            var testSrc = appLibrary.iconSource(cand)
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
    if (!pid || seen[pid]) continue
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
    var alreadyPinned = false
    for (var p = 0; p < pinned.length; p++) {
      if (isAppMatch(pinned[p], rid)) {
        alreadyPinned = true
        break
      }
    }
    if (alreadyPinned || seen[rid]) continue
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
  enrich(runningOut)

  return { pinned: pinnedOut, running: runningOut }
}

// True when the list has at least one window and every one of them is parked
// on the minimized workspace. Used by both the running-icon hide logic and
// the divider gating so the two can never disagree.
//
// liveWsOf/minWs: optional live resolver. The cached isMinimized flag freezes
// at rebuild time and can be stale — Quickshell's Hyprland handle lags silent
// moves onto the special workspace — so callers that can resolve live state
// (the address-based lookup the running-dot uses) must pass it here. A window
// counts as minimized when its cached flag says so OR the live workspace does.
function allWindowsMinimized(windowList, liveWsOf, isMinimizedWs) {
  // toArray, NOT Array.isArray: windowList arrives from the Repeater model as
  // a QVariantList, which Array.isArray rejects — the guard silently emptied
  // every list and made this helper return false forever (v2.9.1 regression).
  var isMinWs = typeof isMinimizedWs === "function"
    ? isMinimizedWs
    : function (name) { return name === "special:minimized" }
  var list = toArray(windowList)
  if (list.length === 0) return false
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (!w) return false
    if (w.isMinimized) continue
    var ws = liveWsOf ? String(liveWsOf(w) || "") : String(w.workspaceName || "")
    if (!isMinWs(ws)) return false
  }
  return true
}

// Which window a click or a wheel step should land on. Pure: the caller
// decides how to bring it forward.
function pickAppWindow(toplevels, activeToplevel, appId, direction) {
  var want = stripDesktop(appId)
  if (!want) return null
  var list = toArray(toplevels)
  var matching = []

  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (t && (stripDesktop(t.appId) === want || isAppMatch(t.appId, want))) matching.push(t)
  }

  if (matching.length === 0) return null
  if (matching.length === 1) return matching[0]

  var dir = (typeof direction === "number" && direction < 0) ? -1 : 1
  var activeIdx = -1
  for (var j = 0; j < matching.length; j++) {
    if (matching[j] === activeToplevel || matching[j].activated) {
      activeIdx = j
      break
    }
  }

  // Nothing of this app is focused: enter the list from the end we came from.
  if (activeIdx < 0) return matching[dir > 0 ? 0 : matching.length - 1]
  return matching[(activeIdx + dir + matching.length) % matching.length]
}

function focusWindow(toplevel) {
  if (toplevel && toplevel.activate) toplevel.activate()
}

function closeApp(toplevels, appId) {
  var want = stripDesktop(appId)
  if (!want) return 0
  var list = toArray(toplevels)
  var closed = 0
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    if (!t) continue
    if (stripDesktop(t.appId) === want || isAppMatch(t.appId, want)) {
      if (t.close) t.close()
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

// Returns an icon name for the caller to resolve through the active icon theme.
// Explicit monochrome modes bypass that and name Adwaita's symbolic file, which
// is the one place a fixed path is correct: no themed lookup yields a folder
// glyph that recolours cleanly.
function resolveThemedFolderIcon(iconName, folderColorMode) {
  var name = String(iconName || "folder").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  // Place aliases with no dedicated icon in the standard place sets
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
    "folder-templates", "folder-videos", "user-home", "user-desktop", "user-trash"
  ]
  if (validPlaces.indexOf(name) < 0) name = "folder"

  if (folderColorMode === "white" || folderColorMode === "black" || folderColorMode === "symbolic") {
    return "file:///usr/share/icons/Adwaita/symbolic/places/" + name + "-symbolic.svg"
  }

  return name
}

function resolveFileItemIcon(iconName, folderColorMode) {
  var name = String(iconName || "text-x-generic").trim()
  if (name.indexOf("/") === 0 || name.indexOf("file://") === 0) return name

  if (name === "folder" || name.indexOf("folder-") === 0 || name === "user-home") {
    return resolveThemedFolderIcon(name, folderColorMode)
  }

  return name
}

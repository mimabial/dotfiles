.pragma library

function isSpecial(ws) {
  return Number(ws.id) < 0 || String(ws.name || "").indexOf("special") === 0;
}

function parseSnapshot(snap) {
  var mons = Array.isArray(snap.monitors) ? snap.monitors : [];
  var monById = {};
  var focusedMon = null;
  for (var i = 0; i < mons.length; i++) {
    monById[mons[i].id] = mons[i];
    if (mons[i].focused === true) focusedMon = mons[i];
  }
  if (!focusedMon && mons.length > 0) focusedMon = mons[0];

  var out = [];
  var clients = Array.isArray(snap.clients) ? snap.clients : [];
  for (var k = 0; k < clients.length; k++) {
    var c = clients[k];
    if (!c || c.mapped === false || !c.address) continue;
    var ws = c.workspace || { id: 0, name: "" };
    if (Number(ws.id) === 0 && String(ws.name || "") === "") continue;
    var mon = monById[c.monitor] || focusedMon;
    out.push({
      address: String(c.address),
      ws: Number(ws.id),
      special: isSpecial(ws),
      monitor: mon ? String(mon.name || "") : "",
      focusId: Number(c.focusHistoryID) >= 0 ? Number(c.focusHistoryID) : 999
    });
  }

  return {
    windows: out,
    focusedMonitor: focusedMon ? String(focusedMon.name || "") : "",
    activeWorkspace: focusedMon && focusedMon.activeWorkspace ? Number(focusedMon.activeWorkspace.id) : 1
  };
}

function switchable(state, cfg) {
  var scope = cfg.scope;
  var items = [];
  var src = state && state.windows ? state.windows : [];
  for (var i = 0; i < src.length; i++) {
    var w = src[i];
    if (w.special && (cfg.showSpecial !== true || scope === "workspace")) continue;
    if (scope === "monitor" && w.monitor !== state.focusedMonitor) continue;
    if (scope === "workspace" && w.ws !== state.activeWorkspace) continue;
    if (scope === "others" && w.ws === state.activeWorkspace) continue;
    items.push(w);
  }

  if (cfg.order === "recent") {
    items.sort(function(a, b) { return a.focusId - b.focusId; });
  } else {
    items.sort(function(a, b) {
      if (a.special !== b.special) return a.special ? 1 : -1;
      if (a.ws !== b.ws) return a.ws - b.ws;
      return a.focusId - b.focusId;
    });
  }
  return items;
}

function cycle(state, cfg, previous, address, step) {
  var items = switchable(state, cfg);
  var available = {};
  for (var i = 0; i < items.length; i++) available[items[i].address] = true;
  var windows = previous.filter(function(key) { return available[key] === true; });
  if (windows.length === 0) {
    windows = items.map(function(item) { return item.address; });
    address = "";
    for (var j = 0; j < state.windows.length; j++)
      if (state.windows[j].focusId === 0) address = state.windows[j].address;
  }
  if (windows.length === 0) return {windows: [], address: ""};
  var index = windows.indexOf(address);
  if (index < 0) index = step > 0 ? -1 : 0;
  return {windows: windows, address: windows[(index + step + windows.length) % windows.length]};
}

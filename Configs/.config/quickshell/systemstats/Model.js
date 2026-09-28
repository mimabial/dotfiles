.pragma library

// Pure helpers shared by the service, bar readouts, and panel pages.
// No state lives here — everything is a function of its arguments.

var MODULES = [
  { id: "cpu",     icon: "󰻠", short: "CPU", label: "CPU",     page: "CpuPage.qml",     graph: true,  ring: true },
  { id: "gpu",     icon: "󰢮", short: "GPU", label: "GPU",     page: "GpuPage.qml",     graph: true,  ring: true },
  { id: "memory",  icon: "󰍛", short: "MEM", label: "Memory",  page: "MemoryPage.qml",  graph: true,  ring: true },
  { id: "disks",   icon: "󰋊", short: "DSK", label: "Disks",   page: "DisksPage.qml",   graph: true,  ring: true },
  { id: "network", icon: "󰛳", short: "NET", label: "Network", page: "NetworkPage.qml", graph: true,  ring: false },
  { id: "sensors", icon: "󰔏", short: "SEN", label: "Sensors", page: "SensorsPage.qml", graph: false, ring: false },
  { id: "battery", icon: "󰁹", short: "BAT", label: "Battery", page: "BatteryPage.qml", graph: false, ring: true },
  { id: "power", icon: "󱐋", short: "PWR", label: "Power", page: "PowerPage.qml", graph: false, ring: false },
  { id: "alerts", icon: "󰀦", short: "ALT", label: "Alerts", page: "AlertsPage.qml", graph: false },
  { id: "settings", icon: "󰒓", short: "SET", label: "Settings", page: "SettingsPage.qml", graph: false }
]

var PANEL_TABS = ["cpu", "gpu", "memory", "disks", "network", "sensors", "battery", "power"]

var ALERTS = [
  { id: "cpuUsage", label: "CPU usage", threshold: 90, step: 5, min: 5, max: 100, unit: "%" },
  { id: "cpuTemp", label: "CPU temperature", threshold: 90, step: 5, min: 40, max: 110, unit: "°C" },
  { id: "gpuUsage", label: "GPU usage", threshold: 95, step: 5, min: 5, max: 100, unit: "%" },
  { id: "gpuTemp", label: "GPU temperature", threshold: 85, step: 5, min: 40, max: 110, unit: "°C" },
  { id: "vram", label: "VRAM usage", threshold: 90, step: 5, min: 5, max: 100, unit: "%" },
  { id: "memory", label: "Memory usage", threshold: 90, step: 5, min: 5, max: 100, unit: "%" },
  { id: "diskUsage", label: "Disk usage", threshold: 90, step: 5, min: 5, max: 100, unit: "%" },
  { id: "driveTemp", label: "Drive temperature", threshold: 70, step: 5, min: 40, max: 110, unit: "°C" },
  { id: "batteryLow", label: "Battery low", threshold: 15, step: 5, min: 5, max: 50, unit: "%", low: true },
  { id: "driveHealth", label: "Drive SMART health", unit: "" }
]

function alertDef(id) {
  for (var i = 0; i < ALERTS.length; i++) if (ALERTS[i].id === id) return ALERTS[i]
  return null
}

function alertReading(snapshot, id) {
  var s = snapshot || {}, cpu = s.cpu || {}, gpu = s.gpu || {}, mem = s.mem || {}
  var disks = s.disks || {}, battery = s.battery || {}
  if (id === "cpuUsage") return { value: cpu.total, subject: "" }
  if (id === "cpuTemp") return { value: cpu.temp, subject: "" }
  if (id === "gpuUsage") return { value: gpu.util, subject: String(gpu.name || "") }
  if (id === "gpuTemp") return { value: gpu.temp, subject: String(gpu.name || "") }
  if (id === "vram") return { value: gpu.memTotal > 0 ? gpu.memUsed / gpu.memTotal * 100 : null, subject: String(gpu.name || "") }
  if (id === "memory") return { value: mem.total > 0 ? mem.used / mem.total * 100 : null, subject: "" }
  if (id === "batteryLow") return { value: battery.present && battery.status === "Discharging" && battery.percent !== null && battery.percent !== undefined ? battery.percent : null, subject: "" }
  if (id === "diskUsage") {
    var volumes = Array.isArray(disks.volumes) ? disks.volumes : [], fullest = null
    for (var i = 0; i < volumes.length; i++) {
      var volume = volumes[i]
      if (!(volume.size > 0) || !isFinite(Number(volume.used))) continue
      var percent = Number(volume.used) / Number(volume.size) * 100
      if (!fullest || percent > fullest.value) fullest = { value: percent, subject: String(volume.mount || volume.device || "") }
    }
    return fullest || { value: null, subject: "" }
  }
  if (id === "driveTemp") {
    var perDisk = disks.perDisk || {}, hottest = null
    for (var name in perDisk) {
      var temp = perDisk[name].temp
      if (temp === null || temp === undefined || !isFinite(Number(temp))) continue
      if (!hottest || Number(temp) > hottest.value) hottest = { value: Number(temp), subject: name }
    }
    return hottest || { value: null, subject: "" }
  }
  return { value: null, subject: "" }
}

function nextAlertState(previous, above, now) {
  var old = previous || { count: 0, active: false, last: 0 }
  if (!above) return { count: 0, active: false, last: old.last || 0, fire: false }
  if (old.active) return { count: old.count, active: true, last: old.last || 0, fire: false }
  var count = old.count + 1
  if (count < 3) return { count: count, active: false, last: old.last || 0, fire: false }
  var fire = now - (old.last || 0) >= 300000
  return { count: count, active: true, last: fire ? now : old.last || 0, fire: fire }
}

// Every user-tunable key with its default. Per-module bar styles live in
// "<module>Style" and fall back to "style" when empty.
var SETTINGS = {
  modules: "cpu,memory,network",
  style: "both",
  cpuStyle: "", gpuStyle: "", memoryStyle: "", disksStyle: "", networkStyle: "", sensorsStyle: "", batteryStyle: "",
  graphWidth: 36,
  barLabels: "text",
  disksSource: "all",
  barSensors: "cpu",
  temperatureUnit: "Celsius",
  colorTemperatureIcons: true,
  refreshSeconds: 1,
  historySeconds: 240,
  historySpan: "live",
  publicIp: true,
  tabs: "cpu,gpu,memory,disks,network,sensors,battery,power",
  showProcesses: true,
  showCores: true, showLoad: true,
  showBreakdown: true,
  showVolumes: true, showActivity: true,
  showInterfaces: true, showTotals: true, showAddresses: true,
  showTemperatures: true, showFans: true,
  showHistory: true, showDetails: true, showDevices: true
}

// Sections each page can hide, as shown on the Settings page.
var PANEL_SECTIONS = {
  cpu: [
    { key: "showCores", label: "Per-core rings" },
    { key: "showLoad", label: "Load average and uptime" }
  ],
  memory: [
    { key: "showBreakdown", label: "Breakdown" }
  ],
  disks: [
    { key: "showVolumes", label: "Volumes" },
    { key: "showActivity", label: "Read and write activity" }
  ],
  network: [
    { key: "showInterfaces", label: "Interfaces" },
    { key: "showTotals", label: "Totals since boot" },
    { key: "publicIp", label: "Public IP address" },
    { key: "showAddresses", label: "IP addresses" }
  ],
  sensors: [
    { key: "showTemperatures", label: "Temperatures" },
    { key: "showFans", label: "Fans" }
  ],
  battery: [
    { key: "showHistory", label: "Charge history" },
    { key: "showDetails", label: "Details" },
    { key: "showDevices", label: "Devices" }
  ]
}

// Multiple-choice options per page, shown after that page's toggles.
var PANEL_CHOICES = {}

// Sampling intervals offered by the Settings page, in seconds.
var REFRESH_STOPS = [0.1, 0.2, 0.5, 1, 2, 5, 10]

function nearestStopIndex(value) {
  var v = Number(value)
  var best = 3
  var bestDistance = Infinity
  for (var i = 0; i < REFRESH_STOPS.length; i++) {
    var d = Math.abs(Math.log(REFRESH_STOPS[i]) - Math.log(isFinite(v) && v > 0 ? v : 1))
    if (d < bestDistance) { bestDistance = d; best = i }
  }
  return best
}

function intervalText(seconds) {
  var v = Number(seconds)
  if (!isFinite(v) || v <= 0) return "1"
  return v < 1 ? v.toFixed(1) : String(Math.round(v))
}

function parseList(raw) {
  var text = Array.isArray(raw) ? raw.join(",") : String(raw || "")
  var out = []
  var parts = text.split(/[\s,;]+/)
  for (var i = 0; i < parts.length; i++) if (parts[i] && out.indexOf(parts[i]) === -1) out.push(parts[i])
  return out
}

// ---------------------------------------------------------------- sensors

// Friendly row label for a hwmon temperature entry.
function sensorLabel(temp) {
  var chip = String(temp.chip || "")
  var label = String(temp.label || "")
  if (!label || label === chip) return chip
  if (chip === "Board" || chip.indexOf("Board") === 0) return label
  if (label.indexOf(chip) === 0) return label
  return chip + " " + label
}

// Everything the bar's sensor readout can show, as {value, label, kind}.
function sensorOptions(snapshot) {
  var s = snapshot || {}
  var cpu = s.cpu || {}
  var gpu = s.gpu || null
  var sensors = s.sensors || {}
  var out = []
  if (isFinite(Number(cpu.temp)) && cpu.temp !== null) out.push({ value: "cpu", label: "CPU temperature", kind: "temp" })
  var gpuTemp = gpu && gpu.temp !== null && isFinite(Number(gpu.temp)) ? gpu.temp : sensors.gpuTemp
  if (gpuTemp !== null && gpuTemp !== undefined && isFinite(Number(gpuTemp))) out.push({ value: "gpu", label: "GPU temperature", kind: "temp" })
  var temps = Array.isArray(sensors.temps) ? sensors.temps : []
  for (var i = 0; i < temps.length; i++) out.push({ value: String(temps[i].id), label: sensorLabel(temps[i]), kind: "temp" })
  var fans = Array.isArray(sensors.fans) ? sensors.fans : []
  for (var j = 0; j < fans.length; j++) out.push({ value: String(fans[j].id), label: String(fans[j].label || "Fan"), kind: "fan" })
  return out
}

// One reading for the bar: {icon, label, text, unit, kind} or null.
function sensorReading(snapshot, id, unit) {
  var s = snapshot || {}
  var cpu = s.cpu || {}
  var gpu = s.gpu || null
  var sensors = s.sensors || {}
  if (id === "cpu") {
    if (!(isFinite(Number(cpu.temp)) && cpu.temp !== null)) return null
    var c = tempParts(cpu.temp, unit)
    return { icon: "󰻠", short: "CPU", label: "CPU", text: c.value, unit: c.unit, kind: "temp", celsius: cpu.temp }
  }
  if (id === "gpu") {
    var gpuTemp = gpu && gpu.temp !== null && isFinite(Number(gpu.temp)) ? gpu.temp : sensors.gpuTemp
    if (gpuTemp === null || gpuTemp === undefined || !isFinite(Number(gpuTemp))) return null
    var g = tempParts(gpuTemp, unit)
    return { icon: "󰢮", short: "GPU", label: "GPU", text: g.value, unit: g.unit, kind: "temp", celsius: gpuTemp }
  }
  var temps = Array.isArray(sensors.temps) ? sensors.temps : []
  for (var i = 0; i < temps.length; i++) {
    if (String(temps[i].id) === id) {
      var t = tempParts(temps[i].value, unit)
      return { icon: "󰔏", short: "TMP", label: sensorLabel(temps[i]), text: t.value, unit: t.unit, kind: "temp", celsius: temps[i].value, critical: temps[i].critical }
    }
  }
  var fans = Array.isArray(sensors.fans) ? sensors.fans : []
  for (var j = 0; j < fans.length; j++) {
    if (String(fans[j].id) === id) {
      var rpm = num(fans[j].rpm)
      return { icon: "󰈐", short: "FAN", label: String(fans[j].label || "Fan"), text: rpm > 0 ? String(Math.round(rpm)) : "Off", unit: rpm > 0 ? "rpm" : "", kind: "fan", rpm: rpm }
    }
  }
  return null
}

// ------------------------------------------------------------------ disks

function diskOptions(snapshot) {
  var s = snapshot || {}
  var disks = s.disks || {}
  var perDisk = disks.perDisk || {}
  var volumes = Array.isArray(disks.volumes) ? disks.volumes : []
  var models = {}
  for (var i = 0; i < volumes.length; i++) if (volumes[i].disk && volumes[i].model) models[volumes[i].disk] = volumes[i].model
  var out = [{ value: "all", label: "All disks" }]
  var names = Object.keys(perDisk).sort()
  for (var j = 0; j < names.length; j++) {
    var model = models[names[j]] ? " · " + String(models[names[j]]).slice(0, 22) : ""
    out.push({ value: names[j], label: names[j] + model })
  }
  return out
}

// ------------------------------------------------------------- processes

function processSortValue(item, key) {
  if (!item) return 0
  if (key === "io") return num(item.read) + num(item.write)
  if (key === "net") return num(item.rx) + num(item.tx)
  return num(item[key])
}

function filterProcesses(list, query, key) {
  var items = Array.isArray(list) ? list.slice() : []
  var q = String(query || "").trim().toLowerCase()
  if (q) items = items.filter(function(item) { return String(item.name || "").toLowerCase().indexOf(q) !== -1 })
  items.sort(function(a, b) {
    var d = processSortValue(b, key) - processSortValue(a, key)
    return d !== 0 ? d : String(a.name || "").localeCompare(String(b.name || ""))
  })
  return items
}

function settingValue(settings, key) {
  var value = settings ? settings[key] : undefined
  return value === undefined || value === null ? SETTINGS[key] : value
}

function historyRange(value) {
  return value === "1h" ? 1 : value === "24h" ? 2 : 0
}

function truthy(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  if (typeof value === "string") {
    var s = value.trim().toLowerCase()
    if (s === "true" || s === "on" || s === "yes" || s === "1") return true
    if (s === "false" || s === "off" || s === "no" || s === "0") return false
  }
  return value === undefined || value === null ? fallback : !!value
}

function flag(settings, key) {
  return truthy(settingValue(settings, key), SETTINGS[key] === true)
}

// Bar readout looks: graph, ring, text (figure only), both (graph + figure),
// ring-text (ring + figure).
var STYLES = ["graph", "ring", "text", "both", "ring-text"]

function normalizeStyle(value) {
  var mode = String(value || "").toLowerCase().replace("+", "-").replace("_", "-")
  if (mode === "ringtext" || mode === "ring-figure") mode = "ring-text"
  if (mode === "graph-text") mode = "both"
  return STYLES.indexOf(mode) !== -1 ? mode : ""
}

// Style choices offered for one module: rings only where fullness means something.
function styleOptions(module) {
  var def = moduleDef(module)
  var out = []
  if (def.graph) out.push({ value: "graph", label: "Graph" })
  if (def.ring) out.push({ value: "ring", label: "Ring" })
  out.push({ value: "text", label: "Figure" })
  if (def.graph) out.push({ value: "both", label: "Graph and figure" })
  if (def.ring) out.push({ value: "ring-text", label: "Ring and figure" })
  return out
}

// Effective bar style for one module: its own override, else the global one.
function moduleStyle(settings, module) {
  var own = normalizeStyle(settingValue(settings, module + "Style"))
  if (own) return own
  return normalizeStyle(settingValue(settings, "style")) || "both"
}

function moveInList(list, id, delta) {
  var out = list.slice()
  var from = out.indexOf(id)
  if (from < 0) return out
  var to = Math.max(0, Math.min(out.length - 1, from + delta))
  if (to === from) return out
  out.splice(from, 1)
  out.splice(to, 0, id)
  return out
}

function moduleDef(id) {
  for (var i = 0; i < MODULES.length; i++) if (MODULES[i].id === id) return MODULES[i]
  return MODULES[0]
}

function pageFile(tab) {
  return moduleDef(tab).page
}

function tabFor(module) { return module }

function parseModules(raw) {
  var text = Array.isArray(raw) ? raw.join(",") : String(raw || "")
  var parts = text.toLowerCase().split(/[\s,;]+/)
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var id = parts[i]
    if (id === "mem" || id === "ram") id = "memory"
    if (id === "disk" || id === "storage") id = "disks"
    if (id === "net" || id === "wifi") id = "network"
    if (id === "temp" || id === "temps" || id === "sensor") id = "sensors"
    if (id === "bat") id = "battery"
    var known = false
    for (var j = 0; j < MODULES.length; j++) if (MODULES[j].id === id) known = true
    if (known && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

// Module tabs in canonical order, filtered by the "tabs" setting and by the
// hardware present. Never empty: the CPU tab is the floor.
function panelTabs(hasGpu, hasBattery, tabsSetting) {
  var wanted = parseModules(tabsSetting === undefined ? SETTINGS.tabs : tabsSetting)
  var out = []
  for (var i = 0; i < PANEL_TABS.length; i++) {
    var id = PANEL_TABS[i]
    if (id === "gpu" && !hasGpu) continue
    if (id === "battery" && !hasBattery) continue
    if (wanted.indexOf(id) === -1) continue
    out.push(id)
  }
  return out.length > 0 ? out : ["cpu"]
}

function gpuIcon(vendor) {
  var kind = String(vendor || "").toLowerCase()
  return kind === "intel" ? "󰢮" : kind === "nvidia" || kind === "amd" ? "󰾲" : "󰍺"
}

// ------------------------------------------------------------------ numbers

function clamp(v, lo, hi) {
  var n = Number(v)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

var BYTE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]

function bytesParts(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) v = 0
  var i = 0
  while (v >= 1024 && i < BYTE_UNITS.length - 1) { v /= 1024; i++ }
  var text
  if (i <= 1 || v >= 100) text = String(Math.round(v))
  else text = v.toFixed(1)
  return { value: text, unit: BYTE_UNITS[i] }
}

function bytesText(n) {
  var p = bytesParts(n)
  return p.value + " " + p.unit
}

function rateParts(n) {
  var p = bytesParts(n)
  return { value: p.value, unit: p.unit + "/s" }
}

function rateText(n) {
  var p = rateParts(n)
  return p.value + " " + p.unit
}

// Ultra-compact rate for the bar: "0", "34K", "1.2M".
function compactRate(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 512) return "0"
  var p = bytesParts(v)
  return p.value + p.unit.charAt(0)
}

// "1.2 / 24 GB" — drop the unit from the first number when both share it.
function pairText(a, b) {
  var pa = bytesParts(a), pb = bytesParts(b)
  if (pa.unit === pb.unit) return pa.value + " / " + pb.value + " " + pb.unit
  return pa.value + " " + pa.unit + " / " + pb.value + " " + pb.unit
}

function percentParts(v) {
  return { value: String(Math.round(clamp(v, 0, 100))), unit: "%" }
}

function percentText(v) {
  return Math.round(clamp(v, 0, 100)) + "%"
}

function tempValue(celsius, unit) {
  var c = Number(celsius)
  if (!isFinite(c)) return NaN
  return unit === "Fahrenheit" ? c * 9 / 5 + 32 : c
}

function tempParts(celsius, unit) {
  var v = tempValue(celsius, unit)
  if (!isFinite(v)) return { value: "—", unit: "" }
  return { value: String(Math.round(v)), unit: "°" }
}

function tempText(celsius, unit) {
  var p = tempParts(celsius, unit)
  return p.value + p.unit
}

function tempLongText(celsius, unit) {
  var v = tempValue(celsius, unit)
  if (!isFinite(v)) return "—"
  return Math.round(v) + (unit === "Fahrenheit" ? "°F" : "°C")
}

function freqText(mhz) {
  var m = Number(mhz)
  if (!isFinite(m) || m <= 0) return ""
  return m >= 1000 ? (m / 1000).toFixed(2) + " GHz" : Math.round(m) + " MHz"
}

function uptimeText(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  if (m > 0) return m + "m"
  return "<1m"
}

function clockText(minutes) {
  var m = Math.max(0, Math.round(Number(minutes) || 0))
  var h = Math.floor(m / 60)
  var r = m % 60
  return h + ":" + (r < 10 ? "0" : "") + r
}

function loadText(load) {
  if (!Array.isArray(load) || load.length < 3) return "—"
  return load.map(function(v) { return Number(v).toFixed(2) }).join("  ")
}

function volumeName(mount) {
  var m = String(mount || "")
  if (m === "/") return "Root"
  if (m === "/home") return "Home"
  if (m === "/boot" || m === "/boot/efi" || m === "/efi") return "Boot"
  var parts = m.split("/")
  return parts[parts.length - 1] || m
}

function shortGpuName(name) {
  return String(name || "GPU")
    .replace(/^NVIDIA\s+/i, "")
    .replace(/^GeForce\s+/i, "")
    .replace(/^AMD\s+/i, "")
    .replace(/^Radeon\s+/i, "")
    .replace(/^Intel\s+(Corporation\s+)?/i, "")
    .replace(/\s+Graphics$/i, "")
}

function batteryIcon(percent, charging) {
  if (charging) return "󰂄"
  var icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  return icons[Math.round(clamp(percent, 0, 100) / 10)]
}

function wifiIcon(dbm) {
  var d = Number(dbm)
  if (!isFinite(d)) return "󰤨"
  if (d >= -55) return "󰤨"
  if (d >= -65) return "󰤥"
  if (d >= -75) return "󰤢"
  if (d >= -85) return "󰤟"
  return "󰤯"
}

function ifaceIcon(iface) {
  if (!iface) return "󰈀"
  if (iface.wireless) return wifiIcon(iface.dbm)
  if (/^(tun|tap|wg|tailscale|proton|nord|vpn)/.test(iface.name || "")) return "󰖂"
  return "󰈀"
}

function linkSpeedText(iface) {
  if (!iface) return ""
  if (iface.wireless && iface.bitrate) return Math.round(iface.bitrate) + " Mb/s"
  var mbps = Number(iface.speed)
  if (!isFinite(mbps) || mbps <= 0) return ""
  return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s"
}

// ------------------------------------------------------------------ history

function emptyHistory() {
  return {
    cpuUser: [], cpuSystem: [], cpuTotal: [], cpuTemp: [],
    gpu: [], gpuTemp: [], vram: [], gpus: {}, gpuTemps: {}, vrams: {},
    memUsed: [], memPressure: [],
    netRx: [], netTx: [], diskRead: [], diskWrite: [], disks: {},
    battery: [], batteryCharging: []
  }
}

function emptyPeakBucket() { return { slots: [], series: {} } }

var PEAK_HISTORY_KEYS = [
  "cpuUser", "cpuSystem", "cpuTotal", "cpuTemp", "gpu", "gpuTemp", "vram",
  "memUsed", "memPressure", "netRx", "netTx", "diskRead", "diskWrite",
  "batteryEmpty", "batteryCharging"
]

function validPeakKey(key) {
  return PEAK_HISTORY_KEYS.indexOf(key) !== -1
    || /^(gpu|gpuTemp|vram)\/(amd|intel|nvidia)$/.test(key)
    || /^disk\/[A-Za-z0-9_-]{1,64}\/(read|write)$/.test(key)
}

function peakValue(value) {
  if (value === null || value === undefined) return null
  var number = Number(value)
  return isFinite(number) && number >= 0 && number <= 1e15 ? number : null
}

function normalizePeakBucket(raw, limit) {
  if (!raw || !Array.isArray(raw.slots) || !raw.series || typeof raw.series !== "object") return emptyPeakBucket()
  var slots = raw.slots.slice(-limit)
  if (slots.length === 0) return emptyPeakBucket()
  for (var i = 0; i < slots.length; i++) {
    if (!Number.isSafeInteger(slots[i]) || (i > 0 && slots[i] <= slots[i - 1])) return emptyPeakBucket()
  }
  var series = {}
  var keys = Object.keys(raw.series).slice(0, 128)
  for (var j = 0; j < keys.length; j++) {
    var key = keys[j], values = raw.series[key]
    if (!validPeakKey(key) || !Array.isArray(values) || values.length < slots.length) continue
    series[key] = values.slice(-slots.length).map(peakValue)
  }
  return { slots: slots, series: series }
}

function peakBucket(previous, slot, values, limit) {
  var old = previous || emptyPeakBucket()
  var slots = Array.isArray(old.slots) ? old.slots.slice() : []
  var series = {}, oldSeries = old.series || {}
  for (var key in oldSeries) if (Array.isArray(oldSeries[key])) series[key] = oldSeries[key].slice()
  var last = slots.length ? slots[slots.length - 1] : slot - 1
  if (last > slot) { slots = []; series = {}; last = slot - 1 }
  if (last < slot) {
    for (var next = Math.max(last + 1, slot - limit + 1); next <= slot; next++) {
      slots.push(next)
      for (var existing in series) series[existing].push(null)
    }
  }
  var index = slots.length - 1
  for (var current in values) {
    if (!validPeakKey(current)) continue
    if (!series[current]) {
      if (Object.keys(series).length >= 128) continue
      series[current] = Array(slots.length).fill(null)
    }
    var value = peakValue(values[current]), prior = series[current][index]
    if (value !== null) series[current][index] = prior === null || prior === undefined ? value : Math.max(prior, value)
  }
  slots = slots.slice(-limit)
  for (var stored in series) series[stored] = series[stored].slice(-limit)
  return { slots: slots, series: series }
}

function mergePeakBuckets(saved, current, limit) {
  var merged = normalizePeakBucket(saved, limit)
  var recent = normalizePeakBucket(current, limit)
  for (var i = 0; i < recent.slots.length; i++) {
    var values = {}
    for (var key in recent.series) values[key] = recent.series[key][i]
    merged = peakBucket(merged, recent.slots[i], values, limit)
  }
  return merged
}

function peakHistoryView(live, hour, day, range) {
  if (range === 0) return live || emptyHistory()
  var series = (range === 1 ? hour : day).series || {}
  var view = emptyHistory()
  for (var key in series) {
    if (key === "batteryEmpty") view.battery = series[key].map(function(value) { return value === null ? null : 100 - value })
    else if (key.indexOf("gpu/") === 0) view.gpus[key.slice(4)] = series[key]
    else if (key.indexOf("gpuTemp/") === 0) view.gpuTemps[key.slice(8)] = series[key]
    else if (key.indexOf("vram/") === 0) view.vrams[key.slice(5)] = series[key]
    else if (key.indexOf("disk/") === 0) {
      var match = /^disk\/([^/]+)\/(read|write)$/.exec(key)
      if (match) {
        if (!view.disks[match[1]]) view.disks[match[1]] = { read: [], write: [] }
        view.disks[match[1]][match[2]] = series[key]
      }
    } else if (Object.prototype.hasOwnProperty.call(view, key)) view[key] = series[key]
  }
  return view
}

function historyBarWidth(width, range) {
  return range === 0 ? 2 : Math.max(2, Math.floor(Number(width) / 60) - 1)
}

function hasReading(values) {
  if (!Array.isArray(values)) return false
  for (var i = 0; i < values.length; i++) if (peakValue(values[i]) !== null) return true
  return false
}

function pushHistory(arr, value, max) {
  var list = Array.isArray(arr) ? arr : []
  var keep = Math.max(1, max - 1)
  var out = list.length > keep ? list.slice(list.length - keep) : list.slice()
  out.push(value === null || value === undefined || !isFinite(Number(value)) ? null : Number(value))
  return out
}

function powerBucket(previous, slot, cpu, gpu, limit) {
  var old = previous || {}
  var slots = Array.isArray(old.slots) ? old.slots.slice() : []
  var cpus = Array.isArray(old.cpu) ? old.cpu.slice() : []
  var gpus = Array.isArray(old.gpu) ? old.gpu.slice() : []
  var last = slots.length ? slots[slots.length - 1] : slot - 1
  if (last > slot) { slots = []; cpus = []; gpus = []; last = slot - 1 }
  if (last === slot) {
    var end = slots.length - 1
    var nextCpu = peakValue(cpu), nextGpu = peakValue(gpu)
    if (nextCpu !== null) cpus[end] = peakValue(cpus[end]) === null ? nextCpu : Math.max(cpus[end], nextCpu)
    if (nextGpu !== null) gpus[end] = peakValue(gpus[end]) === null ? nextGpu : Math.max(gpus[end], nextGpu)
  } else {
    for (var next = Math.max(last + 1, slot - limit + 1); next <= slot; next++) {
      slots.push(next)
      cpus.push(next === slot ? peakValue(cpu) : null)
      gpus.push(next === slot ? peakValue(gpu) : null)
    }
  }
  return { slots: slots.slice(-limit), cpu: cpus.slice(-limit), gpu: gpus.slice(-limit) }
}

function maxOf(arr, count) {
  if (!Array.isArray(arr) || arr.length === 0) return 0
  var start = count > 0 ? Math.max(0, arr.length - count) : 0
  var m = 0
  for (var i = start; i < arr.length; i++) if (arr[i] > m) m = arr[i]
  return m
}

function last(arr, fallback) {
  if (!Array.isArray(arr) || arr.length === 0) return fallback
  return arr[arr.length - 1]
}

// ------------------------------------------------------------------ palette

var FALLBACK_TEMPERATURE_RAMP = [
  { threshold: 90, color: "#8b0000" }, { threshold: 85, color: "#ad1f2f" },
  { threshold: 80, color: "#d22f2f" }, { threshold: 75, color: "#ff471a" },
  { threshold: 70, color: "#ff6347" }, { threshold: 65, color: "#ff8c00" },
  { threshold: 60, color: "#ffa500" }, { threshold: 45, color: "" },
  { threshold: 40, color: "#add8e6" }, { threshold: 35, color: "#87ceeb" },
  { threshold: 30, color: "#4682b4" }, { threshold: 25, color: "#4169e1" },
  { threshold: 20, color: "#0000ff" }, { threshold: 0, color: "#00008b" }
]

function parseTemperatureRamp(text) {
  var ramp = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*(\d+)\|\s*(#[0-9a-fA-F]{6})?\s*$/)
    if (match) ramp.push({ threshold: Number(match[1]), color: match[2] || "" })
  }
  return ramp.length ? ramp.sort(function(a, b) { return b.threshold - a.threshold }) : FALLBACK_TEMPERATURE_RAMP
}

function temperatureColor(ramp, celsius, critical, fallback) {
  if (celsius === null || celsius === undefined || !isFinite(Number(celsius))) return fallback
  var limit = Number(critical)
  if (!isFinite(limit) || limit <= 0) limit = 100
  var normalized = Number(celsius) * 100 / limit
  var stops = Array.isArray(ramp) && ramp.length ? ramp : FALLBACK_TEMPERATURE_RAMP
  for (var i = 0; i < stops.length; i++) if (normalized >= stops[i].threshold) return stops[i].color || fallback
  return fallback
}

function parseColorsToml(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1]] = m[2]
  }
  return out
}

function hueOf(c) {
  var q = Qt.color(c)
  return q.hslHue < 0 ? -1 : q.hslHue * 360
}

function hueDistance(a, b) {
  if (a < 0 || b < 0) return 0
  var d = Math.abs(a - b) % 360
  return d > 180 ? 360 - d : d
}

function shiftHue(c, degrees, minSaturation) {
  var q = Qt.color(c)
  var h = q.hslHue < 0 ? 0.6 : (q.hslHue + degrees / 360 + 1) % 1
  return Qt.hsla(h, Math.max(minSaturation || 0.45, q.hslSaturation), clamp(q.hslLightness, 0.45, 0.72), 1)
}

// Derive the two-hue iStat scheme from the active theme: series1 is the
// accent; series2 is the theme colour furthest around the wheel from it
// (magenta/cyan/blue preferred), and a tertiary colour covers a third
// category where one is needed. Warn/danger are the theme's yellow/red.
function pickPalette(theme, accent, foreground, background, urgent) {
  var t = theme || {}
  var accentHue = hueOf(accent)
  var bgLight = Qt.color(background).hslLightness
  var names = ["blue", "magenta", "cyan", "green", "yellow", "orange", "red"]
  var candidates = []
  for (var i = 0; i < names.length; i++) {
    var c = t[names[i]]
    if (!c) continue
    var q = Qt.color(c)
    if (q.hslSaturation < 0.2 || Math.abs(q.hslLightness - bgLight) < 0.25) continue
    candidates.push({ name: names[i], color: c, hue: hueOf(c), dist: hueDistance(accentHue, hueOf(c)) })
  }
  candidates.sort(function(a, b) { return b.dist - a.dist })

  var second = null
  for (var j = 0; j < candidates.length; j++) {
    var cand = candidates[j]
    if ((cand.name === "magenta" || cand.name === "cyan" || cand.name === "blue") && cand.dist >= 50) { second = cand; break }
  }
  if (!second && candidates.length > 0 && candidates[0].dist >= 30) second = candidates[0]
  var series2 = second ? second.color : shiftHue(accent, 180)
  var series2Hue = hueOf(series2)

  var tertiary = null
  for (var k = 0; k < candidates.length; k++) {
    var alt = candidates[k]
    if (alt === second) continue
    if (alt.dist >= 35 && hueDistance(alt.hue, series2Hue) >= 35) { tertiary = alt.color; break }
  }
  if (!tertiary) tertiary = t.yellow || shiftHue(accent, 120)

  return {
    series1: accent,
    series2: series2,
    tertiary: tertiary,
    warn: t.yellow || t.orange || tertiary,
    danger: t.red || urgent,
    good: t.green || accent
  }
}

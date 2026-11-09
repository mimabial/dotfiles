.pragma library
.import "../Units.js" as Units

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
  for (var alert of ALERTS) if (alert.id === id) return alert
  return null
}

function alertReading(snapshot, id) {
  snapshot = snapshot || {}
  var cpu = snapshot.cpu || {}, mem = snapshot.mem || {}
  var disks = snapshot.disks || {}, battery = snapshot.battery || {}
  if (id === "cpuUsage") return { value: cpu.total, subject: "" }
  if (id === "cpuTemp") return { value: cpu.temp, subject: "" }
  if (id === "gpuUsage") return highestGpu(snapshot, function(card) { return card.util })
  if (id === "gpuTemp") return highestGpu(snapshot, function(card) { return card.temp })
  if (id === "vram") return highestGpu(snapshot, gpuMemoryPercent)
  if (id === "memory") return { value: mem.total > 0 ? mem.used / mem.total * 100 : null, subject: "" }
  if (id === "batteryLow") return { value: battery.present && battery.status === "Discharging" && battery.percent !== null && battery.percent !== undefined ? battery.percent : null, subject: "" }
  if (id === "diskUsage") {
    var volumes = Array.isArray(disks.volumes) ? disks.volumes : [], fullest = null
    for (var volume of volumes) {
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

function highestGpu(snapshot, reading) {
  var highest = { value: null, subject: "" }
  for (var card of gpuList(snapshot)) {
    var value = reading(card)
    if (finiteValue(value) && (highest.value === null || Number(value) > highest.value)) highest = { value: Number(value), subject: gpuTitle(card) }
  }
  return highest
}

function nextAlertState(previous, above, now) {
  var old = previous || { count: 0, active: false, last: 0 }
  if (!above) return { count: 0, active: false, last: old.last || 0, fire: false }
  if (old.active) return { count: old.count, active: true, last: old.last || 0, fire: false }
  var count = old.count + 1
  if (count < ALERT_CONFIRMATIONS) return { count: count, active: false, last: old.last || 0, fire: false }
  var fire = now - (old.last || 0) >= ALERT_REPEAT_MS
  return { count: count, active: true, last: fire ? now : old.last || 0, fire: fire }
}

// Per-module bar styles live in "<module>Style" and fall back to "style" when empty.
var SETTINGS = {
  modules: "cpu,memory,network",
  style: "both",
  cpuStyle: "", gpuStyle: "", memoryStyle: "", disksStyle: "", networkStyle: "", sensorsStyle: "", batteryStyle: "",
  graphWidth: 36,
  barLabels: "text",
  disksSource: "all",
  barDisks: "",
  barGpus: "discrete",
  showGpuMemory: false,
  barSensors: "cpu",
  temperatureUnit: "Celsius",
  colorTemperatureIcons: true,
  utilizationColors: false,
  utilizationLowColor: "", utilizationNormalColor: "", utilizationWarningColor: "", utilizationCriticalColor: "",
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
  showTemperatures: true,
  showHistory: true, showDetails: true, showDevices: true
}

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
    { key: "showTemperatures", label: "Temperatures" }
  ],
  battery: [
    { key: "showHistory", label: "Charge history" },
    { key: "showDetails", label: "Details" },
    { key: "showDevices", label: "Devices" }
  ]
}

var PANEL_CHOICES = {}

var DETAIL_NONE = 0
var DETAIL_TOP_PROCESSES = 1
var DETAIL_ALL_PROCESSES = 2

var REFRESH_STOPS_SECONDS = [0.1, 0.2, 0.5, 1, 2, 5, 10]
var HISTORY_STOPS_SECONDS = [30, 60, 120, 240, 300, 600, 900, 1800, 3600]
var MIN_REFRESH_SECONDS = 0.1
var MAX_REFRESH_SECONDS = 30
var TEMPERATURE_SCALE_FLOOR = 30
var NETWORK_SCALE_FLOOR = 10 * 1024
var DISK_SCALE_FLOOR = 256 * 1024
var DISK_WARN = 0.8
var DISK_DANGER = 0.92
var PRESSURE_WARN_PERCENT = 10
var PRESSURE_DANGER_PERCENT = 40
var STALL_BUSY_PERCENT = 90
var STALL_PRESSURE_PERCENT = 20
var SLOW_BUSY_PERCENT = 50
var SLOW_SSD_LATENCY_MS = 20
var SLOW_HDD_LATENCY_MS = 100
var SENSOR_WARN = 0.78
var SENSOR_DANGER = 0.92
var SENSOR_FALLBACK_CRITICAL = 95
var SWAP_WARN = 0.5
var SWAP_DANGER = 0.85
var BATTERY_LOW_PERCENT = 20
var BATTERY_CRITICAL_PERCENT = 10
var SENSOR_ALERT_MIN = 40
var SENSOR_ALERT_MAX = 120
var SENSOR_ALERT_STEP = 5
var ALERT_CONFIRMATIONS = 3
var ALERT_REPEAT_MS = 5 * Units.MS_PER_MINUTE

function nearestStopIndex(value, stops) {
  var requested = Number(value)
  var best = 0
  var bestDistance = Infinity
  for (var i = 0; i < stops.length; i++) {
    var distance = Math.abs(Math.log(stops[i]) - Math.log(isFinite(requested) && requested > 0 ? requested : 1))
    if (distance < bestDistance) { bestDistance = distance; best = i }
  }
  return best
}

function intervalText(seconds) {
  var amount = Number(seconds)
  if (!isFinite(amount) || amount <= 0) return "1"
  return amount < 1 ? amount.toFixed(1) : String(Math.round(amount))
}

function parseList(raw) {
  var text = Array.isArray(raw) ? raw.join(",") : String(raw || "")
  var out = []
  var parts = text.split(/[\s,;]+/)
  for (var part of parts) if (part && out.indexOf(part) === -1) out.push(part)
  return out
}

function finiteValue(value) {
  return value !== null && value !== undefined && value !== "" && isFinite(Number(value))
}

function primarySensorGpu(snapshot) {
  for (var card of discreteGpus(snapshot)) if (finiteValue(card.temp)) return card
  return null
}

function sensorTemps(snapshot) {
  var sensors = (snapshot || {}).sensors || {}
  var out = Array.isArray(sensors.temps) ? sensors.temps.slice() : []
  for (var card of gpuList(snapshot)) {
    if (card.vendor === "nvidia" && finiteValue(card.temp))
      out.push({ chip: "GPU", id: "gpu:" + gpuId(card), alertId: "gpu:" + gpuId(card), label: gpuTitle(card), title: gpuTitle(card), value: Number(card.temp), max: 0 })
  }
  return out
}

function sensorLabel(temp) {
  if (temp.title) return String(temp.title)
  var chip = String(temp.chip || "")
  var label = String(temp.label || "")
  if (!label || label === chip) return chip
  if (chip === "Board" || chip.indexOf("Board") === 0) return label
  if (label.indexOf(chip) === 0) return label
  return chip + " " + label
}

function sensorOptions(snapshot) {
  snapshot = snapshot || {}
  var cpu = snapshot.cpu || {}
  var out = []
  if (finiteValue(cpu.temp)) out.push({ value: "cpu", label: "CPU temperature", kind: "temp" })
  if (finiteValue(sensorGpuTemp(snapshot))) out.push({ value: "gpu", label: "GPU temperature", kind: "temp" })
  for (var temp of sensorTemps(snapshot)) out.push({ value: String(temp.id), label: sensorLabel(temp), kind: "temp" })
  return out
}

// One reading for the bar: {icon, label, text, unit, kind} or null.
function sensorReading(snapshot, id, unit) {
  snapshot = snapshot || {}
  var cpu = snapshot.cpu || {}
  if (id === "cpu") {
    if (!(isFinite(Number(cpu.temp)) && cpu.temp !== null)) return null
    var cpuParts = tempParts(cpu.temp, unit)
    return { icon: "󰻠", short: "CPU", label: "CPU", text: cpuParts.value, unit: cpuParts.unit, kind: "temp", celsius: cpu.temp }
  }
  if (id === "gpu") {
    var gpuTemp = sensorGpuTemp(snapshot)
    if (!finiteValue(gpuTemp)) return null
    var gpuParts = tempParts(gpuTemp, unit)
    return { icon: "󰢮", short: "GPU", label: "GPU", text: gpuParts.value, unit: gpuParts.unit, kind: "temp", celsius: gpuTemp }
  }
  for (var temp of sensorTemps(snapshot)) {
    if (String(temp.id) === id) {
      var reading = tempParts(temp.value, unit)
      return { icon: "󰔏", short: temp.chip === "GPU" ? gpuShort(gpuById(snapshot, id.slice(4))) : "TMP", label: sensorLabel(temp), text: reading.value, unit: reading.unit, kind: "temp", celsius: temp.value, critical: temp.critical }
    }
  }
  return null
}

function sensorGpuTemp(snapshot) {
  var card = primarySensorGpu(snapshot)
  return card ? card.temp : ((snapshot || {}).sensors || {}).gpuTemp
}

function diskOptions(snapshot) {
  snapshot = snapshot || {}
  var disks = snapshot.disks || {}
  var perDisk = disks.perDisk || {}
  var volumes = Array.isArray(disks.volumes) ? disks.volumes : []
  var models = {}
  for (var volume of volumes) if (volume.disk && volume.model) models[volume.disk] = volume.model
  var out = [{ value: "all", label: "All disks" }]
  var names = Object.keys(perDisk).sort()
  for (var name of names) {
    var model = models[name] ? " · " + String(models[name]).slice(0, 22) : ""
    out.push({ value: diskId(snapshot, name), label: name + model })
  }
  return out
}

function diskId(snapshot, name) {
  var entry = (((snapshot || {}).disks || {}).perDisk || {})[name]
  return entry && entry.id ? String(entry.id) : String(name || "")
}

function resolveDisk(snapshot, value) {
  var saved = String(value || "")
  if (!saved || saved === "all") return "all"
  var perDisk = ((snapshot || {}).disks || {}).perDisk || {}
  for (var name in perDisk) if (perDisk[name] && String(perDisk[name].id) === saved) return name
  return perDisk[saved] ? saved : ""
}

function stableDiskId(snapshot, value) {
  var name = resolveDisk(snapshot, value)
  return name === "" ? String(value || "") : (name === "all" ? "all" : diskId(snapshot, name))
}

function stableSettings(settings, snapshot) {
  var perDisk = ((snapshot || {}).disks || {}).perDisk || {}
  if (Object.keys(perDisk).length === 0) return null
  var out = {}, changed = false
  var raw = String(settingValue(settings, "barDisks") || "").trim()
  if (raw && raw.toLowerCase() !== "none") {
    var list = barDisks(settings)
    var text = barDisksText(list.map(function(entry) { return { disk: stableDiskId(snapshot, entry.disk), show: entry.show } }))
    if (text !== barDisksText(list)) { out.barDisks = text; changed = true }
  }
  var source = String(settingValue(settings, "disksSource") || "").trim()
  if (source && stableDiskId(snapshot, source) !== source) { out.disksSource = stableDiskId(snapshot, source); changed = true }
  return changed ? out : null
}

var DISK_SHOWS = [
  { value: "speed", label: "Speed" },
  { value: "used", label: "Used" },
  { value: "both", label: "Both" }
]

function normalizeDiskShow(value) {
  var show = String(value || "").toLowerCase()
  for (var option of DISK_SHOWS) if (option.value === show) return show
  return ""
}

function barDisks(settings) {
  var raw = String(settingValue(settings, "barDisks") || "").trim()
  if (raw.toLowerCase() === "none") return []
  if (!raw) {
    var style = moduleStyle(settings, "disks")
    return [{ disk: String(settingValue(settings, "disksSource") || "all").trim() || "all", show: style === "ring" || style === "ring-text" ? "used" : "speed" }]
  }
  var out = [], seen = []
  for (var part of parseList(raw)) {
    var at = part.lastIndexOf(":")
    var show = at === -1 ? "" : normalizeDiskShow(part.slice(at + 1))
    var disk = show ? part.slice(0, at) : part
    if (disk.toLowerCase() === "all") disk = "all"
    if (!disk || seen.indexOf(disk) !== -1) continue
    seen.push(disk)
    out.push({ disk: disk, show: show || "speed" })
  }
  return out
}

function barDisksHere(snapshot, settings) {
  var list = barDisks(settings)
  var perDisk = ((snapshot || {}).disks || {}).perDisk || {}
  if (list.length === 0 || Object.keys(perDisk).length === 0) return list
  for (var entry of list) if (resolveDisk(snapshot, entry.disk) !== "") return list
  return [{ disk: "all", show: list[0].show }]
}

function barDisksText(list) {
  if (!list || list.length === 0) return "none"
  return list.map(function(entry) { return entry.disk + ":" + entry.show }).join(",")
}

function diskShort(disk) {
  var name = String(disk || "")
  if (!name || name === "all") return "DSK"
  var match = name.match(/^nvme(\d+)n\d+$/) || name.match(/^mmcblk(\d+)$/)
  if (match) return (name.indexOf("nvme") === 0 ? "NV" : "MC") + match[1]
  return name.replace(/[^A-Za-z0-9]/g, "").slice(0, 3).toUpperCase() || "DSK"
}

function diskUsage(snapshot, disk) {
  var disks = (snapshot || {}).disks || {}
  var perDisk = disks.perDisk || {}
  var volumes = Array.isArray(disks.volumes) ? disks.volumes : []
  var used = 0, size = 0
  for (var volume of volumes) {
    if (disk === "all" ? !perDisk[volume.disk] && volume.fstype !== "zfs" : volume.disk !== disk) continue
    used += num(volume.used)
    size += num(volume.size)
  }
  if (size <= 0 && disk === "all") {
    for (var root of volumes) if (root.mount === "/") { used = num(root.used); size = num(root.size) }
  }
  return { used: used, size: size, fraction: size > 0 ? clamp(used / size, 0, 1) : 0 }
}

function pressureColor(percent, calm, warn, danger) {
  var share = num(percent)
  return share >= PRESSURE_DANGER_PERCENT ? danger : (share >= PRESSURE_WARN_PERCENT ? warn : calm)
}

var VOLUME_KINDS = [
  { kind: "internal", title: "Internal" },
  { kind: "external", title: "External" },
  { kind: "network", title: "Network" }
]

function volumeGroups(volumes) {
  var list = Array.isArray(volumes) ? volumes : []
  var out = []
  for (var group of VOLUME_KINDS) {
    var items = list.filter(function(volume) { return String(volume.kind || "internal") === group.kind })
    if (items.length) out.push({ kind: group.kind, title: group.title, items: items })
  }
  return out
}

function volumeKey(volume) {
  return volume ? String(volume.key || volume.disk || volume.device || "") : ""
}

function latencyText(milliseconds) {
  var value = Number(milliseconds)
  if (milliseconds === null || milliseconds === undefined || !isFinite(value)) return "—"
  if (value < 1) return (Math.round(value * 100) / 100) + " ms"
  if (value < 10) return (Math.round(value * 10) / 10) + " ms"
  return Math.round(value) + " ms"
}

function driveHealth(load, pressureFull, rotational) {
  if (!load) return { level: "", text: "" }
  var busy = num(load.busy)
  var latency = finiteValue(load.latency) ? Number(load.latency) : NaN
  if (busy >= STALL_BUSY_PERCENT && num(pressureFull) >= STALL_PRESSURE_PERCENT)
    return { level: "danger", text: "Stalling the system: busy " + Math.round(busy) + "% of the time while every task waits on I/O" }
  if (isFinite(latency) && busy >= SLOW_BUSY_PERCENT && latency >= (rotational ? SLOW_HDD_LATENCY_MS : SLOW_SSD_LATENCY_MS))
    return { level: "warn", text: "Slow to answer: " + latencyText(latency) + " per request" }
  return { level: "", text: "" }
}

function checkText(check) {
  var current = check || {}
  if (current.id === "trim-blocked") return {
    title: "TRIM never reaches this drive",
    detail: "The encrypted volume " + (current.layer || "") + " was unlocked without allowing discards, so fstrim can't trim it "
      + "and the SSD is never told which blocks are free. It slows down as it fills and wears faster."
      + (current.fix ? "" : " Unlock it with discards allowed (allow-discards in crypttab, or rd.luks.options=discard)."),
    fixLabel: "Allow TRIM"
  }
  if (current.id === "trim-stale") return {
    title: "TRIM still stops at the LVM volumes",
    detail: "TRIM now passes through " + (current.layer || "") + ", but the LVM volumes on top of it were set up before that and still drop it."
      + (current.fix ? " Reloading them picks it up without a restart." : " They pick it up at the next boot; run sudo fstrim -av after restarting."),
    fixLabel: "Reload volumes"
  }
  if (current.id === "fat-flush") {
    var flags = Array.isArray(current.flags) ? current.flags.join(", ") : "flush"
    return {
      title: "Every file written waits for the drive",
      detail: "Mounted with " + flags + ": closing each written file waits for the drive, so copying many small files crawls."
        + (current.fix ? " The fix mounts it without that option from now on; eject it before unplugging." : " Mount it without " + flags + " to fix it."),
      fixLabel: "Mount without flush"
    }
  }
  return { title: String(current.id || "Check"), detail: "", fixLabel: "Fix" }
}

var FIX_SCRIPTS = {
  "allow-discards": {
    args: 1,
    body: 'echo "Let TRIM pass through the encrypted volume $1 to the SSD."\n'
      + 'echo "This runs: sudo cryptsetup refresh --allow-discards --persistent $1"\n'
      + 'echo "The setting is stored in the LUKS header, so it lasts across reboots."\n'
      + 'on_top=$(volumes_on "$1")\n'
      + 'if [ -n "$on_top" ]; then echo "Then it reloads the volumes on top of it so they pass TRIM too:" $on_top; fi\n'
      + 'confirm || exit 1\n'
      + 'sudo cryptsetup refresh --allow-discards --persistent "$1" || exit 1\n'
      + 'reload_volumes $on_top || exit 1\n'
      + 'echo "Trimming free space now:"\n'
      + 'sudo fstrim -av\n'
  },
  "reload-volumes": {
    args: 1,
    body: 'on_top=$(volumes_on "$1")\n'
      + 'echo "Reload the volumes on top of $1 so they pass TRIM:" $on_top\n'
      + 'echo "Each one pauses for an instant while its unchanged table is loaded again."\n'
      + 'confirm || exit 1\n'
      + 'reload_volumes $on_top || exit 1\n'
      + 'echo "Trimming free space now:"\n'
      + 'sudo fstrim -av\n'
  },
  "udisks-no-flush": {
    args: 2,
    body: 'conf=/etc/udisks2/mount_options.conf\n'
      + 'echo "Mount the FAT drive $2 without flush from now on, so small writes are fast."\n'
      + 'echo "This adds a section for it to $conf, then unmounts and mounts it again."\n'
      + 'confirm || exit 1\n'
      + 'if ! grep -qsF "[/dev/disk/by-uuid/$1]" "$conf"; then\n'
      + '  printf \'\\n[/dev/disk/by-uuid/%s]\\nvfat_defaults=uid=$UID,gid=$GID,shortname=mixed,utf8=1,showexec\\n\' "$1" | sudo tee -a "$conf" >/dev/null || exit 1\n'
      + 'fi\n'
      + 'udisksctl unmount -b "$2" && udisksctl mount -b "$2"\n'
  }
}

var FIX_PRELUDE = 'confirm() { printf "Continue? [y/N] "; read -r answer; [ "$answer" = y ] || [ "$answer" = Y ]; }\n'
  + 'volumes_on() { for name in "/sys/class/block/$(basename "$(readlink -f "/dev/mapper/$1")")"/holders/*/dm/name; do [ -e "$name" ] && cat "$name"; done; }\n'
  + 'reload_volumes() { for volume; do echo "Reloading $volume"; table=$(sudo dmsetup table "$volume") && printf "%s\\n" "$table" | sudo dmsetup reload "$volume" && sudo dmsetup resume "$volume" || return 1; done; }\n'
var FIX_EPILOGUE = 'status=$?\necho\nif [ "$status" -eq 0 ]; then echo "Done."; else echo "Nothing changed, or it failed (status $status)."; fi\n'
  + 'printf "Press Enter to close. "; read -r _\n'

function fixArgOk(value) {
  var text = String(value === undefined || value === null ? "" : value)
  return text.length > 0 && text.length <= 128 && /^[A-Za-z0-9._:\/-]+$/.test(text) && text.indexOf("..") === -1
}

function fixCommand(check) {
  var current = check || {}
  var spec = FIX_SCRIPTS[String(current.fix || "")]
  var args = Array.isArray(current.args) ? current.args : []
  if (!spec || args.length !== spec.args || !args.every(fixArgOk)) return null
  return ["tui-terminal-exec", "--title", "System stats fix", "--", "sh", "-c", FIX_PRELUDE + "(\n" + spec.body + ")\n" + FIX_EPILOGUE, "systemstats-fix"].concat(args.map(String))
}

function driveChecks(volumes, key) {
  var out = [], byProblem = {}
  for (var volume of (Array.isArray(volumes) ? volumes : [])) {
    if (key && key !== "all" && volumeKey(volume) !== key) continue
    for (var check of (Array.isArray(volume.checks) ? volume.checks : [])) {
      var problem = JSON.stringify([check.id, check.layer, check.args])
      if (!byProblem[problem]) out.push(byProblem[problem] = { check: check, names: [] })
      byProblem[problem].names.push(volumeName(volume.mount))
    }
  }
  return out
}

function processSortValue(item, key) {
  if (!item) return 0
  if (key === "io") return num(item.read) + num(item.write)
  if (key === "net") return num(item.rx) + num(item.tx)
  return num(item[key])
}

function filterProcesses(list, query, key) {
  var items = Array.isArray(list) ? list.slice() : []
  var needle = String(query || "").trim().toLowerCase()
  if (needle) items = items.filter(function(item) { return String(item.name || "").toLowerCase().indexOf(needle) !== -1 })
  items.sort(function(a, b) {
    var difference = processSortValue(b, key) - processSortValue(a, key)
    return difference !== 0 ? difference : String(a.name || "").localeCompare(String(b.name || ""))
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

function utilizationGrade(value) {
  if (!finiteValue(value)) return -1
  var percent = Math.round(clamp(value, 0, 100))
  return percent < 25 ? 0 : (percent < 60 ? 1 : (percent < 85 ? 2 : 3))
}

function validHexColor(value) {
  return typeof value === "string" && /^#[0-9A-Fa-f]{6}$/.test(value)
}

var UTILIZATION_KEYS = ["utilizationLowColor", "utilizationNormalColor", "utilizationWarningColor", "utilizationCriticalColor"]
var UTILIZATION_DARK = ["#72ca9b", "#759cd1", "#da9c6c", "#d67471"]
var UTILIZATION_LIGHT = ["#277944", "#3569aa", "#9c6019", "#af4444"]

function utilizationSettingColor(settings, key, lightTheme) {
  var chosen = settingValue(settings, key)
  return validHexColor(chosen) ? chosen : (lightTheme ? UTILIZATION_LIGHT : UTILIZATION_DARK)[UTILIZATION_KEYS.indexOf(key)]
}

function utilizationColor(settings, value, lightTheme) {
  var grade = utilizationGrade(value)
  return flag(settings, "utilizationColors") && grade >= 0 ? utilizationSettingColor(settings, UTILIZATION_KEYS[grade], lightTheme) : null
}

function utilizationHistoryColors(values, settings, lightTheme) {
  if (!flag(settings, "utilizationColors")) return []
  return (Array.isArray(values) ? values : []).map(function(value) { return utilizationColor(settings, value, lightTheme) })
}

function truthy(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "number") return value !== 0
  if (typeof value === "string") {
    var word = value.trim().toLowerCase()
    if (word === "true" || word === "on" || word === "yes" || word === "1") return true
    if (word === "false" || word === "off" || word === "no" || word === "0") return false
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

function styleOptions(module) {
  var def = moduleDef(module)
  var out = []
  if (module === "disks") return [
    { value: "graph", label: "Graph or ring" },
    { value: "text", label: "Figure" },
    { value: "both", label: "Graph or ring, and figure" }
  ]
  if (def.graph) out.push({ value: "graph", label: "Graph" })
  if (def.ring) out.push({ value: "ring", label: "Ring" })
  out.push({ value: "text", label: "Figure" })
  if (def.graph) out.push({ value: "both", label: "Graph and figure" })
  if (def.ring) out.push({ value: "ring-text", label: "Ring and figure" })
  return out
}

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
  for (var module of MODULES) if (module.id === id) return module
  return MODULES[0]
}

function pageFile(tab) {
  return moduleDef(tab).page
}

function tabFor(module) { return module === "gpuMemory" ? "gpu" : module }

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
    for (var module of MODULES) if (module.id === id) known = true
    if (known && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function panelTabs(hasGpu, hasBattery, tabsSetting) {
  var wanted = parseModules(tabsSetting === undefined ? SETTINGS.tabs : tabsSetting)
  var out = []
  for (var id of PANEL_TABS) {
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

function clamp(v, lo, hi) {
  var n = Number(v)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

function rateParts(bytesPerSecond) {
  var parts = Units.bytesParts(bytesPerSecond)
  return { value: parts.value, unit: parts.unit + "/s" }
}

function compactRate(bytesPerSecond) {
  var rate = Number(bytesPerSecond)
  if (!isFinite(rate) || rate < 1024 / 2) return "0"
  var parts = Units.bytesParts(rate)
  return parts.value + parts.unit.charAt(0)
}

function pairText(first, second) {
  var firstParts = Units.bytesParts(first), secondParts = Units.bytesParts(second)
  if (firstParts.unit === secondParts.unit) return firstParts.value + " / " + secondParts.value + " " + secondParts.unit
  return firstParts.value + " " + firstParts.unit + " / " + secondParts.value + " " + secondParts.unit
}

function percentParts(percent) {
  return { value: String(Math.round(clamp(percent, 0, 100))), unit: "%" }
}

function percentText(percent) {
  return Math.round(clamp(percent, 0, 100)) + "%"
}

function tempValue(celsius, unit) {
  var degrees = Number(celsius)
  if (!isFinite(degrees)) return NaN
  return unit === "Fahrenheit" ? degrees * 9 / 5 + 32 : degrees
}

function tempParts(celsius, unit) {
  var converted = tempValue(celsius, unit)
  if (!isFinite(converted)) return { value: "—", unit: "" }
  return { value: String(Math.round(converted)), unit: "°" }
}

function tempText(celsius, unit) {
  var parts = tempParts(celsius, unit)
  return parts.value + parts.unit
}

function freqText(mhz) {
  var megahertz = Number(mhz)
  if (!isFinite(megahertz) || megahertz <= 0) return ""
  return megahertz >= 1000 ? (megahertz / 1000).toFixed(2) + " GHz" : Math.round(megahertz) + " MHz"
}

function clockText(minutes) {
  var total = Math.max(0, Math.round(Number(minutes) || 0))
  var hours = Math.floor(total / 60)
  var remainder = total % 60
  return hours + ":" + (remainder < 10 ? "0" : "") + remainder
}

function loadText(load) {
  if (!Array.isArray(load) || load.length < 3) return "—"
  return load.map(function(average) { return Number(average).toFixed(2) }).join("  ")
}

function volumeName(mount) {
  var path = String(mount || "")
  if (path === "/") return "Root"
  if (path === "/home") return "Home"
  if (path === "/boot" || path === "/boot/efi" || path === "/efi") return "Boot"
  var parts = path.split("/")
  return parts[parts.length - 1] || path
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

function gpuList(snapshot) {
  var cards = (snapshot || {}).gpus
  return Array.isArray(cards) ? cards : []
}

function gpuId(card) {
  return card && card.id !== undefined && card.id !== null ? String(card.id) : ""
}

function gpuById(snapshot, id) {
  for (var card of gpuList(snapshot)) if (gpuId(card) === id) return card
  return null
}

function discreteGpus(snapshot) {
  var cards = gpuList(snapshot)
  var discrete = cards.filter(function(card) { return !card.integrated })
  return discrete.length > 0 ? discrete : cards
}

function selectedGpus(snapshot, raw) {
  var text = String(raw === undefined || raw === null ? SETTINGS.barGpus : raw).trim().toLowerCase()
  if (!text || text === "discrete") return discreteGpus(snapshot)
  if (text === "all") return gpuList(snapshot)
  if (text === "none") return []
  var picked = parseList(text).map(function(id) { return gpuById(snapshot, id) }).filter(function(card) { return !!card })
  return picked.length > 0 ? picked : discreteGpus(snapshot)
}

function gpuShort(card) {
  var vendor = card ? String(card.vendor || "") : ""
  return vendor === "nvidia" ? "NVD" : vendor === "amd" ? "AMD" : vendor === "intel" ? "INT" : "GPU"
}

function gpuTitle(card) {
  return shortGpuName(card ? card.name : "") || gpuShort(card)
}

function gpuHasUtil(card) {
  return !!card && finiteValue(card.util)
}

function gpuMemoryPercent(card) {
  if (!card || !finiteValue(card.memUsed) || !finiteValue(card.memTotal) || Number(card.memTotal) <= 0) return null
  return Math.min(100, Number(card.memUsed) / Number(card.memTotal) * 100)
}

function compactFreq(mhz) {
  var megahertz = Number(mhz)
  if (!isFinite(megahertz) || megahertz <= 0) return "—"
  return megahertz >= 1000 ? (megahertz / 1000).toFixed(1) + "G" : Math.round(megahertz) + "M"
}

function cpuPackageWatts(snapshot) {
  var domains = (((snapshot || {}).power || {}).domains) || []
  var total = null
  for (var domain of domains) if (/^package/.test(String(domain.name)) && finiteValue(domain.watts)) total = (total || 0) + Number(domain.watts)
  return total
}

function powerTotal(snapshot) {
  var battery = (snapshot || {}).battery || {}
  var domains = (((snapshot || {}).power || {}).domains) || []
  var platform = domains.find(function(domain) { return String(domain.name) === "psys" && finiteValue(domain.watts) })
  if (battery.present && battery.status === "Discharging" && num(battery.power) > 0)
    return { watts: Number(battery.power), detail: "Drawn from the battery" }
  if (platform) return { watts: Number(platform.watts), detail: "Platform, measured by RAPL" }
  var cpu = cpuPackageWatts(snapshot), gpu = null
  for (var card of gpuList(snapshot)) if (!card.integrated && finiteValue(card.power)) gpu = (gpu || 0) + Number(card.power)
  if (cpu === null && gpu === null) return { watts: null, detail: "" }
  return { watts: (cpu || 0) + (gpu || 0), detail: gpu !== null ? "CPU and GPUs only" : "CPU package only" }
}

function batteryIcon(percent, charging) {
  if (charging) return "󰂄"
  var icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  return icons[Math.round(clamp(percent, 0, 100) / 10)]
}

var WIFI_SIGNAL_ICONS = [[-55, "󰤨"], [-65, "󰤥"], [-75, "󰤢"], [-85, "󰤟"]]

function wifiIcon(dbm) {
  var signal = Number(dbm)
  if (!isFinite(signal)) return WIFI_SIGNAL_ICONS[0][1]
  for (var [minimumDbm, icon] of WIFI_SIGNAL_ICONS) if (signal >= minimumDbm) return icon
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

function emptyHistory() {
  return {
    cpuUser: [], cpuSystem: [], cpuTotal: [], cpuTemp: [], cpuPower: [], powerTotal: [], ioPressure: [],
    gpuTemp: [], gpus: {}, gpuTemps: {}, gpuPowers: {}, vrams: {},
    memUsed: [], memPressure: [],
    netRx: [], netTx: [], diskRead: [], diskWrite: [], disks: {},
    battery: [], batteryCharging: []
  }
}

function emptyPeakBucket() { return { slots: [], series: {} } }

var PEAK_SERIES_LIMIT = 128
var PEAK_HISTORY_KEYS = [
  "cpuUser", "cpuSystem", "cpuTotal", "cpuTemp", "cpuPower", "gpuTemp",
  "memUsed", "memPressure", "netRx", "netTx", "diskRead", "diskWrite", "powerTotal", "ioPressure",
  "batteryEmpty", "batteryCharging"
]

function validPeakKey(key) {
  return PEAK_HISTORY_KEYS.indexOf(key) !== -1
    || /^(gpu|gpuTemp|gpuPower|vram)\/[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]$/.test(key)
    || /^disk\/[A-Za-z0-9_-]{1,64}\/(read|write)$/.test(key)
}

function peakValue(value) {
  if (value === null || value === undefined) return null
  var number = Number(value)
  return isFinite(number) && number >= 0 && number <= 1e15 ? number : null
}

function raisesPeak(previous, current) {
  var value = peakValue(current)
  return value !== null && (peakValue(previous) === null || value > Number(previous))
}

function normalizePeakBucket(raw, limit) {
  if (!raw || !Array.isArray(raw.slots) || !raw.series || typeof raw.series !== "object") return emptyPeakBucket()
  var slots = raw.slots.slice(-limit)
  if (slots.length === 0) return emptyPeakBucket()
  for (var i = 0; i < slots.length; i++) {
    if (!Number.isSafeInteger(slots[i]) || (i > 0 && slots[i] <= slots[i - 1])) return emptyPeakBucket()
  }
  var series = {}
  var keys = Object.keys(raw.series).slice(0, PEAK_SERIES_LIMIT)
  for (var key of keys) {
    var values = raw.series[key]
    if (!validPeakKey(key) || !Array.isArray(values) || values.length < slots.length) continue
    series[key] = values.slice(-slots.length).map(peakValue)
  }
  return { slots: slots, series: series }
}

function peakBucket(previous, slot, values, limit) {
  var old = previous || emptyPeakBucket(), oldSeries = old.series || {}
  var previousSlots = Array.isArray(old.slots) ? old.slots : [], end = previousSlots.length - 1
  if (previousSlots[end] === slot && previousSlots.length <= limit && Object.keys(values).every(function(key) {
    return !validPeakKey(key) || Array.isArray(oldSeries[key]) && !raisesPeak(oldSeries[key][end], values[key])
  })) return old
  var slots = previousSlots.slice(), series = {}
  for (var key in oldSeries) if (Array.isArray(oldSeries[key])) series[key] = oldSeries[key].slice()
  var last = slots.length ? slots[slots.length - 1] : slot - 1
  if (last > slot) { slots = []; series = {}; last = slot - 1 }
  if (last < slot) {
    for (var next = Math.max(last + 1, slot - limit + 1); next <= slot; next++) {
      slots.push(next)
      for (var existing in series) series[existing].push(null)
    }
  }
  var index = slots.length - 1, seriesCount = Object.keys(series).length
  for (var current in values) {
    if (!validPeakKey(current)) continue
    if (!series[current]) {
      if (seriesCount >= PEAK_SERIES_LIMIT) continue
      series[current] = Array(slots.length).fill(null)
      seriesCount++
    }
    var value = peakValue(values[current]), prior = series[current][index]
    if (value !== null) series[current][index] = prior === null || prior === undefined ? value : Math.max(prior, value)
  }
  if (slots.length > limit) {
    var excess = slots.length - limit
    slots.splice(0, excess)
    for (var stored in series) series[stored].splice(0, excess)
  }
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
    else if (key.indexOf("gpuPower/") === 0) view.gpuPowers[key.slice(9)] = series[key]
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
  for (var value of values) if (peakValue(value) !== null) return true
  return false
}

function pushHistory(arr, value, max) {
  var list = Array.isArray(arr) ? arr : []
  var keep = Math.max(1, max - 1)
  var out = list.length > keep ? list.slice(list.length - keep) : list.slice()
  out.push(value === null || value === undefined || !isFinite(Number(value)) ? null : Number(value))
  return out
}

function maxOf(arr, count) {
  if (!Array.isArray(arr) || arr.length === 0) return 0
  var start = count > 0 ? Math.max(0, arr.length - count) : 0
  var largest = 0
  for (var i = start; i < arr.length; i++) if (arr[i] > largest) largest = arr[i]
  return largest
}

function last(arr, fallback) {
  if (!Array.isArray(arr) || arr.length === 0) return fallback
  return arr[arr.length - 1]
}

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
  for (var line of lines) {
    var match = line.match(/^\s*(\d+)\|\s*(#[0-9a-fA-F]{6})?\s*$/)
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
  for (var stop of stops) if (normalized >= stop.threshold) return stop.color || fallback
  return fallback
}

function hueOf(color) {
  var parsed = Qt.color(color)
  return parsed.hslHue < 0 ? -1 : parsed.hslHue * 360
}

function hueDistance(a, b) {
  if (a < 0 || b < 0) return 0
  var gap = Math.abs(a - b) % 360
  return gap > 180 ? 360 - gap : gap
}

function shiftHue(color, degrees, minSaturation) {
  var parsed = Qt.color(color)
  var hue = parsed.hslHue < 0 ? 0.6 : (parsed.hslHue + degrees / 360 + 1) % 1
  return Qt.hsla(hue, Math.max(minSaturation || 0.45, parsed.hslSaturation), clamp(parsed.hslLightness, 0.45, 0.72), 1)
}

function pickPalette(theme, accent, foreground, background, urgent) {
  theme = theme || {}
  var accentHue = hueOf(accent)
  var bgLight = Qt.color(background).hslLightness
  var names = ["blue", "magenta", "cyan", "green", "yellow", "orange", "red"]
  var candidates = []
  for (var i = 0; i < names.length; i++) {
    var color = theme[names[i]]
    if (!color) continue
    var parsed = Qt.color(color)
    if (parsed.hslSaturation < 0.2 || Math.abs(parsed.hslLightness - bgLight) < 0.25) continue
    candidates.push({ name: names[i], color: color, hue: hueOf(color), dist: hueDistance(accentHue, hueOf(color)) })
  }
  candidates.sort(function(a, b) { return b.dist - a.dist })

  var second = null
  for (var candidate of candidates) {
    if ((candidate.name === "magenta" || candidate.name === "cyan" || candidate.name === "blue") && candidate.dist >= 50) { second = candidate; break }
  }
  if (!second && candidates.length > 0 && candidates[0].dist >= 30) second = candidates[0]
  var series2 = second ? second.color : shiftHue(accent, 180)
  var series2Hue = hueOf(series2)

  var tertiary = null
  for (var candidate of candidates) {
    if (candidate === second) continue
    if (candidate.dist >= 35 && hueDistance(candidate.hue, series2Hue) >= 35) { tertiary = candidate.color; break }
  }
  if (!tertiary) tertiary = theme.yellow || shiftHue(accent, 120)

  return {
    series1: accent,
    series2: series2,
    tertiary: tertiary,
    warn: theme.yellow || theme.orange || tertiary,
    danger: theme.red || urgent,
    good: theme.green || accent
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "Model.js" as Model

// One sampler process per shell, shared by every bar instance on every
// monitor. Holds the latest snapshot, the rolling histories the graphs draw
// from, and the theme-derived two-hue palette.
Item {
  id: root

  required property var shell

  property var snapshot: ({})
  property var history: Model.emptyHistory()
  property var historyHour: Model.emptyPeakBucket()
  property var historyDay: Model.emptyPeakBucket()
  property bool historyLoaded: false
  property int seq: -1
  property bool ready: false
  property string samplerError: ""
  property int historyLength: 240
  property real historySeconds: 240
  property real intervalSeconds: 1
  property int detailRefs: 0
  property int fullRefs: 0
  property int sentDetail: 0
  property string focusPage: ""
  property int restartCount: 0
  property var instances: []
  property var temperatureRamp: Model.FALLBACK_TEMPERATURE_RAMP
  property bool destroying: false
  property var alertConfig: ({ enabled: {}, thresholds: {}, sensorThresholds: {}, alertCommand: "" })
  property var alertEvents: []
  property bool alertsReady: false
  property bool alertDetailHeld: false
  property var alertStates: ({})
  property var driveLevels: ({})
  property var powerFine: ({ cpu: [], gpu: [] })
  property var powerHour: ({ slots: [], cpu: [], gpu: [] })
  property var powerDay: ({ slots: [], cpu: [], gpu: [] })
  property real peakCpuPower: -1
  property real peakGpuPower: -1
  property real cpuEnergyWh: 0
  property real gpuEnergyWh: 0

  readonly property var themeColors: ({
    red: shell.role("c1", shell.urgent),
    green: shell.role("c2", shell.accent),
    yellow: shell.role("c3", shell.accent),
    blue: shell.role("c4", shell.accent),
    magenta: shell.role("c5", shell.accent),
    cyan: shell.role("c6", shell.accent)
  })
  readonly property var statsPalette: Model.pickPalette(themeColors, shell.accent, shell.foreground, shell.background, shell.urgent)
  readonly property color series1: statsPalette.series1
  readonly property color series2: statsPalette.series2
  readonly property color tertiary: statsPalette.tertiary
  readonly property color warn: statsPalette.warn
  readonly property color danger: statsPalette.danger
  readonly property color good: statsPalette.good

  readonly property bool hasGpu: !!(snapshot && snapshot.gpu)
  readonly property bool hasBattery: !!(snapshot && snapshot.battery && snapshot.battery.present)
  readonly property string samplerPath: Qt.resolvedUrl("systemstats_sampler.py").toString().replace(/^file:\/\//, "")

  function ingest(line) {
    var text = String(line || "")
    if (!text || text.length > 524288) return
    var data
    try { data = JSON.parse(text) } catch (error) { return }
    if (!data || typeof data !== "object") return

    var h = root.history
    var n = root.historyLength
    var cpu = data.cpu || {}
    var mem = data.mem || {}
    var net = data.net || {}
    var disks = data.disks || {}
    var gpu = data.gpu
    var battery = data.battery
    var power = data.power || {}
    var domains = Array.isArray(power.domains) ? power.domains : []
    var cpuPower = null
    for (var d = 0; d < domains.length; d++) {
      if (/^package/.test(String(domains[d].name)) && domains[d].watts !== null && isFinite(Number(domains[d].watts)))
        cpuPower = (cpuPower || 0) + Number(domains[d].watts)
    }
    var gpuPower = gpu && gpu.power !== null && gpu.power !== undefined && isFinite(Number(gpu.power)) ? Number(gpu.power) : null
    var elapsed = Number(data.elapsed)
    if (isFinite(elapsed) && elapsed > 0 && elapsed <= Math.max(1, Number(data.interval) * 2)) {
      if (cpuPower !== null) cpuEnergyWh += cpuPower * elapsed / 3600
      if (gpuPower !== null) gpuEnergyWh += gpuPower * elapsed / 3600
    }
    if (cpuPower !== null) peakCpuPower = Math.max(peakCpuPower, cpuPower)
    if (gpuPower !== null) peakGpuPower = Math.max(peakGpuPower, gpuPower)
    var fineLength = Math.min(1200, Math.max(12, Math.ceil(120 / Math.max(0.1, Number(data.interval) || 1))))
    powerFine = {
      cpu: Model.pushHistory(powerFine.cpu, cpuPower, fineLength),
      gpu: Model.pushHistory(powerFine.gpu, gpuPower, fineLength)
    }
    var minute = Math.floor(Number(data.t) / 60)
    var priorMinute = powerHour.slots.length ? powerHour.slots[powerHour.slots.length - 1] : -1
    powerHour = Model.powerBucket(powerHour, minute, cpuPower, gpuPower, 60)
    powerDay = Model.powerBucket(powerDay, Math.floor(minute / 24), cpuPower, gpuPower, 60)
    if (minute !== priorMinute && (cpuPower !== null || gpuPower !== null || priorMinute >= 0))
      powerFile.setText(JSON.stringify({ hour: powerHour, day: powerDay }) + "\n")
    var memPercent = mem.total > 0 ? mem.used / mem.total * 100 : null
    var gpuPercent = gpu && gpu.util !== null && gpu.util !== undefined ? gpu.util : null
    var gpuTemp = gpu && gpu.temp !== null && gpu.temp !== undefined ? gpu.temp : null
    var vramPercent = gpu && gpu.memTotal > 0 ? gpu.memUsed / gpu.memTotal * 100 : null
    var values = {
      cpuUser: cpu.user, cpuSystem: cpu.system, cpuTotal: cpu.total, cpuTemp: cpu.temp,
      gpu: gpuPercent, gpuTemp: gpuTemp, vram: vramPercent,
      memUsed: memPercent, memPressure: mem.pressureSome,
      netRx: net.rx, netTx: net.tx, diskRead: disks.read, diskWrite: disks.write,
      batteryEmpty: battery && battery.present && battery.percent !== null && battery.percent !== undefined ? 100 - Number(battery.percent) : null,
      batteryCharging: battery && battery.present ? (battery.status === "Charging" ? 1 : 0) : null
    }
    var perDisk = disks.perDisk || {}
    var diskHistory = {}
    for (var name in perDisk) {
      var previous = h.disks && h.disks[name] ? h.disks[name] : { read: [], write: [] }
      diskHistory[name] = {
        read: Model.pushHistory(previous.read, perDisk[name].read, n),
        write: Model.pushHistory(previous.write, perDisk[name].write, n)
      }
      values["disk/" + name + "/read"] = perDisk[name].read
      values["disk/" + name + "/write"] = perDisk[name].write
    }
    var gpuHistory = {}
    var gpuTempHistory = {}, vramHistory = {}
    var gpuDevices = gpu && Array.isArray(gpu.devices) ? gpu.devices : []
    for (var i = 0; i < gpuDevices.length; i++) {
      var vendor = String(gpuDevices[i].vendor || "")
      if (vendor) {
        var device = gpuDevices[i]
        var deviceVram = device.memTotal > 0 ? device.memUsed / device.memTotal * 100 : null
        gpuHistory[vendor] = Model.pushHistory(h.gpus && h.gpus[vendor], device.util, n)
        gpuTempHistory[vendor] = Model.pushHistory(h.gpuTemps && h.gpuTemps[vendor], device.temp, n)
        vramHistory[vendor] = Model.pushHistory(h.vrams && h.vrams[vendor], deviceVram, n)
        values["gpu/" + vendor] = device.util
        values["gpuTemp/" + vendor] = device.temp
        values["vram/" + vendor] = deviceVram
      }
    }

    root.history = {
      cpuUser: Model.pushHistory(h.cpuUser, cpu.user, n),
      cpuSystem: Model.pushHistory(h.cpuSystem, cpu.system, n),
      cpuTotal: Model.pushHistory(h.cpuTotal, cpu.total, n),
      cpuTemp: Model.pushHistory(h.cpuTemp, cpu.temp, n),
      gpu: Model.pushHistory(h.gpu, gpuPercent, n),
      gpuTemp: Model.pushHistory(h.gpuTemp, gpuTemp, n),
      vram: Model.pushHistory(h.vram, vramPercent, n),
      gpus: gpuHistory,
      gpuTemps: gpuTempHistory,
      vrams: vramHistory,
      memUsed: Model.pushHistory(h.memUsed, memPercent, n),
      memPressure: Model.pushHistory(h.memPressure, mem.pressureSome, n),
      netRx: Model.pushHistory(h.netRx, net.rx, n),
      netTx: Model.pushHistory(h.netTx, net.tx, n),
      diskRead: Model.pushHistory(h.diskRead, disks.read, n),
      diskWrite: Model.pushHistory(h.diskWrite, disks.write, n),
      disks: diskHistory,
      battery: Model.pushHistory(h.battery, battery && battery.present ? battery.percent : null, n),
      batteryCharging: Model.pushHistory(h.batteryCharging, battery && battery.status === "Charging" ? 1 : 0, n)
    }
    var historyMinute = Math.floor(Number(data.t) / 60)
    var previousHistoryMinute = historyHour.slots.length ? historyHour.slots[historyHour.slots.length - 1] : -1
    historyHour = Model.peakBucket(historyHour, historyMinute, values, 60)
    historyDay = Model.peakBucket(historyDay, Math.floor(historyMinute / 24), values, 60)
    if (historyLoaded && historyMinute !== previousHistoryMinute)
      historyFile.setText(JSON.stringify({ version: 1, hour: historyHour, day: historyDay }) + "\n")
    root.snapshot = data
    root.seq = Number(data.seq) || 0
    root.ready = true
    root.samplerError = Array.isArray(data.errors) && data.errors.length > 0 ? data.errors.join("; ") : ""
    root.evaluateMetricAlerts(data)
  }

  function loadAlertConfig(raw) {
    var previous = alertConfig
    try {
      var parsed = JSON.parse(String(raw))
      alertConfig = {
        enabled: parsed.enabled && typeof parsed.enabled === "object" ? parsed.enabled : {},
        thresholds: parsed.thresholds && typeof parsed.thresholds === "object" ? parsed.thresholds : {},
        sensorThresholds: parsed.sensorThresholds && typeof parsed.sensorThresholds === "object" ? parsed.sensorThresholds : {},
        alertCommand: typeof parsed.alertCommand === "string" ? parsed.alertCommand : ""
      }
    } catch (error) { alertConfig = ({ enabled: {}, thresholds: {}, sensorThresholds: {}, alertCommand: "" }) }
    var states = Object.assign({}, alertStates)
    for (var i = 0; i < Model.ALERTS.length; i++) {
      var key = Model.ALERTS[i].id
      if ((previous.enabled[key] === true) !== alertEnabled(key) || previous.thresholds[key] !== alertConfig.thresholds[key]) {
        delete states[key]
        if (key === "driveHealth") driveLevels = ({})
      }
    }
    for (var stateKey in states) {
      if (stateKey.indexOf("sensor:") !== 0) continue
      var sensorId = stateKey.slice(7)
      if (previous.sensorThresholds[sensorId] !== alertConfig.sensorThresholds[sensorId]) delete states[stateKey]
    }
    alertStates = states
    alertsReady = true
    syncAlertSources()
  }

  function alertEnabled(key) { return alertConfig.enabled[key] === true }

  function alertThreshold(key) {
    var def = Model.alertDef(key)
    if (!def || def.threshold === undefined) return 0
    return Model.clamp(alertConfig.thresholds[key] === undefined ? def.threshold : alertConfig.thresholds[key], def.min, def.max)
  }

  function saveAlertConfig(next) {
    alertConfig = next
    alertConfigFile.setText(JSON.stringify(next, null, 2) + "\n")
    syncAlertSources()
  }

  function setAlertEnabled(key, enabled) {
    if (!Model.alertDef(key)) return
    var flags = Object.assign({}, alertConfig.enabled)
    flags[key] = enabled === true
    var states = Object.assign({}, alertStates)
    delete states[key]
    alertStates = states
    if (key === "driveHealth") driveLevels = ({})
    saveAlertConfig(Object.assign({}, alertConfig, { enabled: flags }))
  }

  function setAlertThreshold(key, value) {
    var def = Model.alertDef(key)
    if (!def || def.threshold === undefined) return
    var thresholds = Object.assign({}, alertConfig.thresholds)
    thresholds[key] = Model.clamp(value, def.min, def.max)
    var states = Object.assign({}, alertStates)
    delete states[key]
    alertStates = states
    saveAlertConfig(Object.assign({}, alertConfig, { thresholds: thresholds }))
  }

  function sensorThreshold(id) {
    var value = alertConfig.sensorThresholds[String(id)]
    return value === undefined || value === null || !isFinite(Number(value)) ? -1 : Model.clamp(value, 40, 120)
  }

  function setSensorThreshold(id, value) {
    var key = String(id || "")
    if (!key) return
    var thresholds = Object.assign({}, alertConfig.sensorThresholds)
    if (value === null || value === undefined) delete thresholds[key]
    else thresholds[key] = Math.round(Model.clamp(value, 40, 120) / 5) * 5
    var states = Object.assign({}, alertStates)
    delete states["sensor:" + key]
    alertStates = states
    saveAlertConfig(Object.assign({}, alertConfig, { sensorThresholds: thresholds }))
  }

  function setAlertCommand(command) {
    saveAlertConfig(Object.assign({}, alertConfig, { alertCommand: String(command || "").slice(0, 4096) }))
  }

  function syncAlertSources() {
    if (!alertsReady) return
    var needsProcesses = alertEnabled("cpuUsage") || alertEnabled("cpuTemp") || alertEnabled("memory")
    if (needsProcesses !== alertDetailHeld) {
      alertDetailHeld = needsProcesses
      if (needsProcesses) acquireDetail()
      else releaseDetail()
    }
    Removable.healthAlertsEnabled = alertEnabled("driveHealth")
    if (Removable.healthAlertsEnabled) evaluateDriveHealth()
  }

  function alertValue(data, key) {
    return Model.alertReading(data, key).value
  }

  function contextLines(data, drive) {
    var cpu = data.cpu || {}, gpu = data.gpu || {}, mem = data.mem || {}, procs = data.procs || {}
    var lines = []
    if (isFinite(Number(cpu.total)) && cpu.total !== null) lines.push("CPU " + Math.round(cpu.total) + "%")
    if (isFinite(Number(cpu.temp)) && cpu.temp !== null) lines.push("CPU temp " + Math.round(cpu.temp) + "°C")
    if (isFinite(Number(gpu.util)) && gpu.util !== null) lines.push("GPU " + Math.round(gpu.util) + "%")
    if (isFinite(Number(gpu.temp)) && gpu.temp !== null) lines.push("GPU temp " + Math.round(gpu.temp) + "°C")
    var vram = Model.alertReading(data, "vram").value
    if (vram !== null && vram !== undefined && isFinite(Number(vram))) lines.push("VRAM " + Math.round(vram) + "%")
    if (mem.total > 0) lines.push("Memory " + Math.round(mem.used / mem.total * 100) + "%")
    var disk = Model.alertReading(data, "diskUsage")
    if (disk.value !== null) lines.push("Disk " + disk.subject + " " + Math.round(disk.value) + "%")
    if (data.battery && data.battery.present && data.battery.percent !== null && data.battery.percent !== undefined)
      lines.push("Battery " + Math.round(data.battery.percent) + "%")
    if (Array.isArray(procs.cpu) && procs.cpu.length) lines.push("Top CPU: " + procs.cpu[0].name + " " + Math.round(procs.cpu[0].cpu) + "%")
    if (Array.isArray(procs.mem) && procs.mem.length) lines.push("Top memory: " + procs.mem[0].name + " " + Model.bytesText(procs.mem[0].mem))
    if (drive) lines.push("Drive: " + drive.title + " · " + drive.health.text + (drive.health.temperature ? " · " + drive.health.temperature : ""))
    return lines
  }

  function fireAlert(key, title, message, data, drive) {
    var event = { at: Date.now(), key: key, title: title, message: message, context: contextLines(data || {}, drive) }
    alertEvents = [event].concat(alertEvents).slice(0, 20)
    alertLogFile.setText(JSON.stringify(alertEvents, null, 2) + "\n")
    var urgency = key === "cpuTemp" || key === "gpuTemp" || key === "driveTemp" || key === "batteryLow" || key === "driveHealth" || key.indexOf("sensor:") === 0 ? "critical" : "normal"
    Quickshell.execDetached(["notify-send", "-a", "System stats", "-u", urgency, title, message])
    if (alertConfig.alertCommand) Quickshell.execDetached([
      "/usr/bin/env", "SYSTEMSTATS_ALERT_KEY=" + key, "SYSTEMSTATS_ALERT_TEXT=" + title + ": " + message,
      "SYSTEMSTATS_ALERT_CRITICAL=" + (urgency === "critical" ? "1" : "0"), "SYSTEMSTATS_ALERT_AT=" + event.at,
      "/bin/sh", "-c", alertConfig.alertCommand
    ])
  }

  function clearAlertEvents() {
    alertEvents = []
    alertLogFile.setText("[]\n")
  }

  function evaluateMetricAlerts(data) {
    if (!alertsReady) return
    var now = Date.now(), states = Object.assign({}, alertStates)
    for (var i = 0; i < Model.ALERTS.length; i++) {
      var def = Model.ALERTS[i]
      if (def.id === "driveHealth" || !alertEnabled(def.id)) continue
      var reading = Model.alertReading(data, def.id), value = reading.value
      var valid = value !== null && value !== undefined && isFinite(Number(value))
      var state = Model.nextAlertState(states[def.id], valid && (def.low ? Number(value) <= alertThreshold(def.id) : Number(value) >= alertThreshold(def.id)), now)
      states[def.id] = state
      if (state.fire) {
        var message = (reading.subject ? reading.subject + ": " : "") + Math.round(Number(value)) + def.unit
          + " reached the " + alertThreshold(def.id) + def.unit + " limit"
        var top = data.procs && (def.id === "memory" ? data.procs.mem : (def.id === "cpuUsage" || def.id === "cpuTemp" ? data.procs.cpu : null))
        if (Array.isArray(top) && top.length) message += " · top process: " + top[0].name
        fireAlert(def.id, def.label, message, data, null)
      }
    }
    var temps = data.sensors && Array.isArray(data.sensors.temps) ? data.sensors.temps : []
    var seenSensors = {}
    for (var j = 0; j < temps.length; j++) {
      var sensor = temps[j], sensorId = String(sensor.alertId || "")
      var limit = sensorThreshold(sensorId)
      if (!sensorId || limit < 0) continue
      var key = "sensor:" + sensorId
      seenSensors[key] = true
      var hot = sensor.value !== null && sensor.value !== undefined && isFinite(Number(sensor.value)) && Number(sensor.value) >= limit
      var sensorState = Model.nextAlertState(states[key], hot, now)
      states[key] = sensorState
      if (sensorState.fire) fireAlert(key, Model.sensorLabel(sensor), Math.round(Number(sensor.value)) + "°C reached the " + limit + "°C limit", data, null)
    }
    for (var activeKey in states) {
      if (activeKey.indexOf("sensor:") === 0 && !seenSensors[activeKey]) states[activeKey] = Model.nextAlertState(states[activeKey], false, now)
    }
    alertStates = states
  }

  function evaluateDriveHealth() {
    if (!alertsReady || !alertEnabled("driveHealth")) return
    var seen = Object.assign({}, driveLevels)
    var devices = Removable.devices.concat(Removable.systemDevices)
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i], health = Removable.healthFor(device)
      if (!health || health.state === "unavailable") continue
      var level = health.state === "failing" ? 2 : health.state === "warning" ? 1 : 0
      var key = Removable.healthKey(device)
      if (level > (seen[key] || 0)) {
        fireAlert("driveHealth", device.title + " drive health", health.text, snapshot,
          { title: device.title, health: health })
      }
      seen[key] = level
    }
    driveLevels = seen
  }

  onAlertConfigChanged: syncAlertSources()

  Connections {
    target: Removable
    function onHealthChanged() { root.evaluateDriveHealth() }
  }

  FileView {
    id: alertConfigFile
    path: root.shell.home + "/.config/quickshell/systemstats/alerts.json"
    watchChanges: true; printErrors: false; atomicWrites: true
    onLoaded: root.loadAlertConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.loadAlertConfig("")
  }

  FileView {
    id: alertLogFile
    path: root.shell.home + "/.local/state/hypr/systemstats-alerts.json"
    watchChanges: true; printErrors: false; atomicWrites: true
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.alertEvents = Array.isArray(parsed) ? parsed.slice(0, 20) : []
      } catch (error) { root.alertEvents = [] }
    }
    onFileChanged: reload()
  }

  function send(text) {
    if (sampler.running) sampler.write(text + "\n")
  }

  // Detail level: 0 nothing, 1 top processes, 2 every process. Open panels
  // hold a detail reference; an expanded process list holds a full one.
  function syncDetail() {
    var level = detailRefs > 0 ? (fullRefs > 0 ? 2 : 1) : 0
    if (level === sentDetail) return
    sentDetail = level
    send("detail " + level)
  }

  function acquireDetail() { detailRefs += 1; syncDetail() }
  function releaseDetail() { detailRefs = Math.max(0, detailRefs - 1); syncDetail() }
  function acquireFull() { fullRefs += 1; syncDetail() }
  function releaseFull() { fullRefs = Math.max(0, fullRefs - 1); syncDetail() }

  // Which page the open panel shows; the sampler adds page-specific extras
  // (per-process connections for the Network page).
  function setFocus(page) {
    var next = String(page || "")
    if (next === focusPage) return
    focusPage = next
    send("focus " + (next || "none"))
  }

  property real publicIpStamp: 0
  property bool publicIpPending: false

  // At most one lookup every ten minutes unless forced (the r key / IPC).
  // A request made before the sampler is up is held until it starts.
  function requestPublicIp(force) {
    var now = Date.now()
    if (!force && now - publicIpStamp < 600000) return
    publicIpStamp = now
    if (sampler.running) send("pubip")
    else publicIpPending = true
  }

  function selectGpu(vendor) {
    var kind = String(vendor || "").toLowerCase()
    if (["amd", "intel", "nvidia"].indexOf(kind) === -1) return
    shell.run(["hyprshell", "gpuinfo", "--use", kind], function() { root.send("gpu " + kind) })
  }

  function configure(refreshSeconds, requestedHistorySeconds) {
    var interval = Model.clamp(refreshSeconds, 0.1, 30)
    var seconds = Model.clamp(requestedHistorySeconds, 30, 3600)
    historySeconds = seconds
    var samples = Math.round(Model.clamp(seconds / interval, 60, 3600))
    if (samples !== historyLength) historyLength = samples
    if (Math.abs(interval - intervalSeconds) > 0.001) {
      intervalSeconds = interval
      send("interval " + interval)
    }
  }

  function registerInstance(item) {
    if (!item || instances.indexOf(item) !== -1) return
    instances = instances.concat([item])
  }

  function unregisterInstance(item) {
    instances = instances.filter(function(existing) { return existing !== item })
  }

  function showTab(tab, mode) {
    var live = instances.filter(function(item) { return !!item })
    var target = String(tab || "")
    for (var i = 0; i < live.length; i++) {
      if (target && typeof live[i].showTab === "function") live[i].showTab(target)
    }
    if (mode === "hide") {
      if (shell.popupName === "systemstats") shell.closePopup()
    } else if (mode === "toggle") {
      shell.togglePopup("systemstats", true)
    } else {
      shell.popupCenteredName = "systemstats"
      shell.popupName = "systemstats"
    }
    return "ok"
  }

  function setHistorySpan(span) {
    var value = String(span || "").toLowerCase()
    if (value === "2m") value = "live"
    if (["live", "1h", "24h"].indexOf(value) === -1) return "unknown history span"
    for (var i = 0; i < instances.length; i++) {
      if (instances[i] && typeof instances[i].persist === "function") {
        instances[i].persist("historySpan", value)
        return "ok"
      }
    }
    return "systemstats unavailable"
  }

  function summary() {
    var s = snapshot || {}
    var cpu = s.cpu || {}
    var mem = s.mem || {}
    var net = s.net || {}
    return {
      ready: ready,
      seq: seq,
      cpu: cpu.total,
      cpuTemp: cpu.temp,
      memoryPercent: mem.total > 0 ? Math.round(mem.used / mem.total * 1000) / 10 : 0,
      download: net.rx,
      upload: net.tx,
      gpu: s.gpu ? s.gpu.util : null,
      battery: s.battery && s.battery.present ? s.battery.percent : null,
      error: samplerError
    }
  }

  FileView {
    id: historyFile
    path: root.shell.home + "/.local/state/quickshell/systemstats-history.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        if (saved.version === 1) {
          root.historyHour = Model.mergePeakBuckets(saved.hour, root.historyHour, 60)
          root.historyDay = Model.mergePeakBuckets(saved.day, root.historyDay, 60)
        }
      } catch (error) {}
      root.historyLoaded = true
    }
    onLoadFailed: root.historyLoaded = true
  }

  FileView {
    id: powerFile
    path: root.shell.home + "/.local/state/quickshell/systemstats-power.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        if (saved.hour && Array.isArray(saved.hour.slots) && Array.isArray(saved.hour.cpu) && Array.isArray(saved.hour.gpu)) root.powerHour = saved.hour
        if (saved.day && Array.isArray(saved.day.slots) && Array.isArray(saved.day.cpu) && Array.isArray(saved.day.gpu)) root.powerDay = saved.day
      } catch (error) {}
    }
  }

  FileView {
    path: root.shell.home + "/.cache/hypr/render/tempramp/ramp.psv"
    watchChanges: true
    printErrors: false
    onLoaded: root.temperatureRamp = Model.parseTemperatureRamp(text())
    onFileChanged: reload()
  }

  Process {
    id: sampler
    command: ["/usr/bin/python3", "-I", root.samplerPath, "--interval", "1"]
    clearEnvironment: true
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
    // Expected diagnostics travel in the bounded JSON stream. Leaving stderr
    // unbound makes Quickshell close that channel instead of buffering it.
    onStarted: {
      if (root.sentDetail > 0) root.send("detail " + root.sentDetail)
      if (root.focusPage) root.send("focus " + root.focusPage)
      if (root.publicIpPending) { root.publicIpPending = false; root.send("pubip") }
      if (Math.abs(root.intervalSeconds - 1) > 0.001) root.send("interval " + root.intervalSeconds)
    }
    onRunningChanged: if (!running) {
      root.ready = false
      if (root.destroying) return
      root.restartCount += 1
      restartTimer.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(5, root.restartCount)))
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    repeat: false
    onTriggered: if (!root.destroying && !sampler.running) sampler.running = true
  }

  // A healthy sampler that has streamed for a while resets the backoff.
  Timer {
    interval: 60000
    repeat: true
    running: root.ready
    onTriggered: root.restartCount = 0
  }

  Component.onDestruction: {
    root.destroying = true
    restartTimer.stop()
    if (sampler.running) {
      sampler.write("quit\n")
      sampler.running = false
    }
  }

  IpcHandler {
    target: "systemstats"

    function status(): string { return JSON.stringify(root.summary()) }
    function refresh(): string { root.requestPublicIp(true); return "ok" }
    function locate(): string {
      return JSON.stringify(root.instances.map(function(item) {
        return item && typeof item.locateSelf === "function" ? item.locateSelf() : null
      }))
    }
    function open(tab: string): string { return root.showTab(tab, "show") }
    function span(value: string): string { return root.setHistorySpan(value) }
    function toggle(tab: string): string { return root.showTab(tab, "toggle") }
    function hide(): string { return root.showTab("", "hide") }
  }
}

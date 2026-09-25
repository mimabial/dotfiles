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
  property var alertConfig: ({ enabled: {}, thresholds: {} })
  property var alertEvents: []
  property bool alertsReady: false
  property bool alertDetailHeld: false
  property var alertStates: ({})
  property var driveLevels: ({})

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
    var memPercent = mem.total > 0 ? mem.used / mem.total * 100 : 0
    var perDisk = disks.perDisk || {}
    var diskHistory = {}
    for (var name in perDisk) {
      var previous = h.disks && h.disks[name] ? h.disks[name] : { read: [], write: [] }
      diskHistory[name] = {
        read: Model.pushHistory(previous.read, perDisk[name].read, n),
        write: Model.pushHistory(previous.write, perDisk[name].write, n)
      }
    }
    var gpuHistory = {}
    var gpuDevices = gpu && Array.isArray(gpu.devices) ? gpu.devices : []
    for (var i = 0; i < gpuDevices.length; i++) {
      var vendor = String(gpuDevices[i].vendor || "")
      if (vendor) gpuHistory[vendor] = Model.pushHistory(h.gpus && h.gpus[vendor], gpuDevices[i].util, n)
    }

    root.history = {
      cpuUser: Model.pushHistory(h.cpuUser, cpu.user, n),
      cpuSystem: Model.pushHistory(h.cpuSystem, cpu.system, n),
      cpuTotal: Model.pushHistory(h.cpuTotal, cpu.total, n),
      gpu: Model.pushHistory(h.gpu, gpu && isFinite(Number(gpu.util)) ? gpu.util : 0, n),
      gpus: gpuHistory,
      memUsed: Model.pushHistory(h.memUsed, memPercent, n),
      memPressure: Model.pushHistory(h.memPressure, mem.pressureSome, n),
      netRx: Model.pushHistory(h.netRx, net.rx, n),
      netTx: Model.pushHistory(h.netTx, net.tx, n),
      diskRead: Model.pushHistory(h.diskRead, disks.read, n),
      diskWrite: Model.pushHistory(h.diskWrite, disks.write, n),
      disks: diskHistory,
      battery: Model.pushHistory(h.battery, battery && battery.present ? battery.percent : 0, n),
      batteryCharging: Model.pushHistory(h.batteryCharging, battery && battery.status === "Charging" ? 1 : 0, n)
    }
    root.snapshot = data
    root.seq = Number(data.seq) || 0
    root.ready = true
    root.samplerError = Array.isArray(data.errors) && data.errors.length > 0 ? data.errors.join("; ") : ""
    root.evaluateMetricAlerts(data)
  }

  function loadAlertConfig(raw) {
    var previouslyEnabled = alertConfig.enabled
    try {
      var parsed = JSON.parse(String(raw))
      alertConfig = {
        enabled: parsed.enabled && typeof parsed.enabled === "object" ? parsed.enabled : {},
        thresholds: parsed.thresholds && typeof parsed.thresholds === "object" ? parsed.thresholds : {}
      }
    } catch (error) { alertConfig = ({ enabled: {}, thresholds: {} }) }
    var states = Object.assign({}, alertStates)
    for (var i = 0; i < Model.ALERTS.length; i++) {
      var key = Model.ALERTS[i].id
      if ((previouslyEnabled[key] === true) !== alertEnabled(key)) {
        delete states[key]
        if (key === "driveHealth") driveLevels = ({})
      }
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
    saveAlertConfig({ enabled: flags, thresholds: alertConfig.thresholds })
  }

  function setAlertThreshold(key, value) {
    var def = Model.alertDef(key)
    if (!def || def.threshold === undefined) return
    var thresholds = Object.assign({}, alertConfig.thresholds)
    thresholds[key] = Model.clamp(value, def.min, def.max)
    var states = Object.assign({}, alertStates)
    delete states[key]
    alertStates = states
    saveAlertConfig({ enabled: alertConfig.enabled, thresholds: thresholds })
  }

  function syncAlertSources() {
    if (!alertsReady) return
    var needsProcesses = alertEnabled("cpuUsage") || alertEnabled("cpuTemp") || alertEnabled("gpuTemp") || alertEnabled("memory")
    if (needsProcesses !== alertDetailHeld) {
      alertDetailHeld = needsProcesses
      if (needsProcesses) acquireDetail()
      else releaseDetail()
    }
    Removable.healthAlertsEnabled = alertEnabled("driveHealth")
    if (Removable.healthAlertsEnabled) evaluateDriveHealth()
  }

  function alertValue(data, key) {
    var cpu = data.cpu || {}, gpu = data.gpu || {}, mem = data.mem || {}
    if (key === "cpuUsage") return cpu.total
    if (key === "cpuTemp") return cpu.temp
    if (key === "gpuTemp") return gpu.temp
    if (key === "memory") return mem.total > 0 ? mem.used / mem.total * 100 : null
    return null
  }

  function contextLines(data, drive) {
    var cpu = data.cpu || {}, gpu = data.gpu || {}, mem = data.mem || {}, procs = data.procs || {}
    var lines = []
    if (isFinite(Number(cpu.total)) && cpu.total !== null) lines.push("CPU " + Math.round(cpu.total) + "%")
    if (isFinite(Number(cpu.temp)) && cpu.temp !== null) lines.push("CPU temp " + Math.round(cpu.temp) + "°C")
    if (isFinite(Number(gpu.util)) && gpu.util !== null) lines.push("GPU " + Math.round(gpu.util) + "%")
    if (isFinite(Number(gpu.temp)) && gpu.temp !== null) lines.push("GPU temp " + Math.round(gpu.temp) + "°C")
    if (mem.total > 0) lines.push("Memory " + Math.round(mem.used / mem.total * 100) + "%")
    if (Array.isArray(procs.cpu) && procs.cpu.length) lines.push("Top CPU: " + procs.cpu[0].name + " " + Math.round(procs.cpu[0].cpu) + "%")
    if (Array.isArray(procs.mem) && procs.mem.length) lines.push("Top memory: " + procs.mem[0].name + " " + Model.bytesText(procs.mem[0].mem))
    if (drive) lines.push("Drive: " + drive.title + " · " + drive.health.text + (drive.health.temperature ? " · " + drive.health.temperature : ""))
    return lines
  }

  function fireAlert(key, title, message, data, drive) {
    var event = { at: Date.now(), key: key, title: title, message: message, context: contextLines(data || {}, drive) }
    alertEvents = [event].concat(alertEvents).slice(0, 20)
    alertLogFile.setText(JSON.stringify(alertEvents, null, 2) + "\n")
    var urgency = key === "cpuTemp" || key === "gpuTemp" || key === "driveHealth" ? "critical" : "normal"
    Quickshell.execDetached(["notify-send", "-a", "System stats", "-u", urgency, title, message])
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
      var value = alertValue(data, def.id)
      var valid = value !== null && value !== undefined && isFinite(Number(value))
      var state = Model.nextAlertState(states[def.id], valid && Number(value) >= alertThreshold(def.id), now)
      states[def.id] = state
      if (state.fire) {
        var reading = Math.round(Number(value)) + def.unit
        var message = reading + " reached the " + alertThreshold(def.id) + def.unit + " limit"
        var top = data.procs && (def.id === "memory" ? data.procs.mem : data.procs.cpu)
        if (Array.isArray(top) && top.length) message += " · top process: " + top[0].name
        fireAlert(def.id, def.label, message, data, null)
      }
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
    function toggle(tab: string): string { return root.showTab(tab, "toggle") }
    function hide(): string { return root.showTab("", "hide") }
  }
}

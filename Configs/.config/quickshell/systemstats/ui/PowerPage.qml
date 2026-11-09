pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../Model.js" as Model

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family
  property int historyRange: 0

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var power: snap.power || ({})
  readonly property var domains: Array.isArray(power.domains) ? power.domains : []
  readonly property var devices: Model.gpuList(snap)
  readonly property var total: Model.powerTotal(snap)
  readonly property var battery: snap.battery || ({})
  readonly property var hist: !service ? Model.emptyHistory()
    : historyRange === 0 ? service.powerFine : Model.peakHistoryView(service.history, service.historyHour, service.historyDay, historyRange)
  readonly property var gpuPeaks: service ? service.gpuPowerPeaks : ({})
  readonly property var gpuEnergy: service ? service.gpuEnergyWh : ({})
  readonly property var poweredGpus: devices.filter(device => Model.gpuId(device) in gpuPeaks || Model.hasReading(hist.gpuPowers[Model.gpuId(device)]))
  readonly property color s1: service ? service.series1 : Commons.Color.accent
  readonly property color s2: service ? service.series2 : Commons.Color.accent

  function hasWatts(value) { return value !== null && value !== undefined && isFinite(Number(value)) && Number(value) >= 0 }
  function watts(value) { return hasWatts(value) ? Number(value).toFixed(1) : "—" }
  function wattsLabel(value) { return hasWatts(value) ? watts(value) + " W" : "—" }
  function wattHoursText(value) { return Number(value) >= 0.05 ? Number(value).toFixed(1) : "—" }
  function raplLabel(name) {
    var label = String(name || "")
    if (/^package/.test(label)) return "CPU " + label.replace("-", " ")
    if (label === "core") return "CPU cores"
    if (label === "uncore") return "CPU uncore"
    if (/dram/i.test(label)) return "Memory (DRAM)"
    if (/psys/i.test(label)) return "Platform"
    return label
  }

  width: parent ? parent.width : implicitWidth
  spacing: Commons.Style.space(10)

  Card {
    visible: root.hasWatts(root.total.watts)
    foreground: root.foreground

    CardHeader { title: "Total"; detail: root.total.detail; foreground: root.foreground; fontFamily: root.fontFamily }
    BigStat {
      width: parent.width
      value: root.watts(root.total.watts)
      unit: "W"
      label: root.battery.present === true ? (root.battery.status === "Discharging" ? "On battery" : "On AC power") : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    HistoryGraph {
      width: parent.width
      height: Commons.Style.space(56)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.hist.powerTotal || []]
      colors: [root.s1]
      baselineColor: Commons.Util.scaleAlpha(root.foreground, 0.14)
    }
  }

  Card {
    foreground: root.foreground

    CardHeader { title: "Measured draw"; foreground: root.foreground; fontFamily: root.fontFamily }

    Repeater {
      model: root.domains.length

      delegate: StatRow {
        required property int index
        readonly property var domain: root.domains[index] || ({})
        label: root.raplLabel(domain.name)
        value: root.watts(domain.watts)
        unit: root.hasWatts(domain.watts) ? "W" : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    Text {
      visible: root.power.restricted === true
      width: parent.width
      text: "CPU energy counters are restricted by the kernel; CPU package draw is unavailable."
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.devices.length

      delegate: StatRow {
        required property int index
        readonly property var device: root.devices[index] || ({})
        label: Model.gpuIcon(device.vendor) + "  " + Model.shortGpuName(device.name)
        detail: device.asleep ? "asleep" : ""
        value: root.watts(device.power)
        unit: root.hasWatts(device.power) ? "W" : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    StatRow {
      visible: root.battery.present === true
      label: root.battery.status === "Charging" ? "Battery charging" : "Battery discharge"
      value: root.watts(root.battery.power)
      unit: root.hasWatts(root.battery.power) ? "W" : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Text {
      visible: root.domains.length === 0 && root.devices.length === 0 && root.battery.present !== true && root.power.restricted !== true
      width: parent.width
      text: "No power sensors are available on this machine."
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }
  }

  Card {
    id: historyCard
    foreground: root.foreground

    CardHeader { title: "Draw history"; detail: "Peak in each time slot"; foreground: root.foreground; fontFamily: root.fontFamily }

    SectionTitle { text: "CPU package · session peak " + root.wattsLabel(root.service ? root.service.peakCpuPower : null); fontFamily: root.fontFamily }
    HistoryGraph {
      width: parent.width
      height: Commons.Style.space(56)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.hist.cpuPower || []]
      colors: [root.s1]
      baselineColor: Commons.Util.scaleAlpha(root.foreground, 0.14)
    }

    Repeater {
      model: root.poweredGpus.length

      delegate: Column {
        id: gpuDraw
        required property int index
        readonly property var device: root.poweredGpus[index] || ({})
        width: parent.width
        spacing: historyCard.spacing

        SectionTitle { text: Model.shortGpuName(gpuDraw.device.name) + " · session peak " + root.wattsLabel(root.gpuPeaks[Model.gpuId(gpuDraw.device)]); fontFamily: root.fontFamily }
        HistoryGraph {
          width: parent.width
          height: Commons.Style.space(56)
          barWidth: Model.historyBarWidth(width, root.historyRange)
          showGaps: root.historyRange > 0
          series: [root.hist.gpuPowers[Model.gpuId(gpuDraw.device)] || []]
          colors: [root.s2]
          baselineColor: Commons.Util.scaleAlpha(root.foreground, 0.14)
        }
      }
    }
  }

  Card {
    foreground: root.foreground

    CardHeader { title: "Session energy"; foreground: root.foreground; fontFamily: root.fontFamily }
    StatRow { label: "CPU package"; value: root.wattHoursText(root.service ? root.service.cpuEnergyWh : 0); unit: value === "—" ? "" : "Wh"; foreground: root.foreground; fontFamily: root.fontFamily }

    Repeater {
      model: root.poweredGpus.length

      delegate: StatRow {
        required property int index
        readonly property var device: root.poweredGpus[index] || ({})
        label: Model.shortGpuName(device.name)
        value: root.wattHoursText(root.gpuEnergy[Model.gpuId(device)] || 0)
        unit: value === "—" ? "" : "Wh"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    Text {
      width: parent.width
      text: "Energy since the shell started, integrated from measured draw. Sources can overlap and are not summed."
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}

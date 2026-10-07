pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "../Model.js" as Model

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property int historyRange: 0

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var power: snap.power || ({})
  readonly property var domains: Array.isArray(power.domains) ? power.domains : []
  readonly property var devices: snap.gpu && Array.isArray(snap.gpu.devices) ? snap.gpu.devices : []
  readonly property var battery: snap.battery || ({})
  readonly property var fine: service ? service.powerFine : ({ cpu: [], gpu: [] })
  readonly property var hour: service ? service.powerHour : ({ cpu: [], gpu: [] })
  readonly property var day: service ? service.powerDay : ({ cpu: [], gpu: [] })
  readonly property var cpuSeries: historyRange === 2 ? day.cpu : historyRange === 1 ? hour.cpu : fine.cpu
  readonly property var gpuSeries: historyRange === 2 ? day.gpu : historyRange === 1 ? hour.gpu : fine.gpu
  readonly property color s1: service ? service.series1 : Color.accent
  readonly property color s2: service ? service.series2 : Color.accent

  function hasWatts(value) { return value !== null && value !== undefined && isFinite(Number(value)) && Number(value) >= 0 }
  function watts(value) { return hasWatts(value) ? Number(value).toFixed(1) : "—" }
  function wattsLabel(value) { return hasWatts(value) ? watts(value) + " W" : "—" }
  function wh(value) { return Number(value) >= 0.05 ? Number(value).toFixed(1) : "—" }
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
  spacing: Style.space(10)

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
      opacity: Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.devices.length

      delegate: StatRow {
        required property int index
        readonly property var device: root.devices[index] || ({})
        label: Model.gpuIcon(device.vendor) + "  " + Model.shortGpuName(device.name)
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
      opacity: Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Card {
    foreground: root.foreground

    CardHeader { title: "Draw history"; detail: "Peak in each time slot"; foreground: root.foreground; fontFamily: root.fontFamily }

    SectionTitle { text: "CPU package · session peak " + root.wattsLabel(root.service ? root.service.peakCpuPower : null); fontFamily: root.fontFamily }
    HistoryGraph {
      width: parent.width
      height: Style.space(56)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.cpuSeries || []]
      colors: [root.s1]
      baselineColor: Util.alpha(root.foreground, 0.14)
    }

    SectionTitle { text: "GPU (selected) · session peak " + root.wattsLabel(root.service ? root.service.peakGpuPower : null); fontFamily: root.fontFamily }
    HistoryGraph {
      width: parent.width
      height: Style.space(56)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.gpuSeries || []]
      colors: [root.s2]
      baselineColor: Util.alpha(root.foreground, 0.14)
    }
  }

  Card {
    foreground: root.foreground

    CardHeader { title: "Session energy"; foreground: root.foreground; fontFamily: root.fontFamily }
    StatRow { label: "CPU package"; value: root.wh(root.service ? root.service.cpuEnergyWh : 0); unit: value === "—" ? "" : "Wh"; foreground: root.foreground; fontFamily: root.fontFamily }
    StatRow { label: "GPU (selected)"; value: root.wh(root.service ? root.service.gpuEnergyWh : 0); unit: value === "—" ? "" : "Wh"; foreground: root.foreground; fontFamily: root.fontFamily }

    Text {
      width: parent.width
      text: "Energy since the shell started, integrated from measured draw. Sources can overlap and are not summed."
      color: root.foreground
      opacity: Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}

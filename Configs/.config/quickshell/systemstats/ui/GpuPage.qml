pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../Model.js" as Model
import "../../Units.js" as Units

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property int historyRange: 0
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var hist: service ? Model.peakHistoryView(service.history, service.historyHour, service.historyDay, historyRange) : Model.emptyHistory()
  readonly property var devices: Model.gpuList(snap)
  readonly property bool lightTheme: foreground.hslLightness < 0.5

  function headerDetail(device) {
    var parts = []
    var frequency = Model.freqText(device.mhz)
    if (frequency) parts.push(frequency)
    if (device.temp !== null && isFinite(Number(device.temp))) parts.push(Model.tempText(device.temp, temperatureUnit))
    return parts.join(", ")
  }

  function graphColor(index) {
    if (!service) return Commons.Color.accent
    return index % 2 ? service.series2 : service.series1
  }

  function tempTextColor(celsius) {
    return Model.flag(settings, "colorTemperatureIcons") && service
      ? Model.temperatureColor(service.temperatureRamp, celsius, 100, foreground) : foreground
  }

  width: parent ? parent.width : implicitWidth
  spacing: Commons.Style.space(10)

  Repeater {
    model: root.devices.length

    delegate: Card {
      id: gpuCard
      required property int index
      readonly property var device: root.devices[index] || ({})
      readonly property color seriesColor: root.graphColor(index)
      readonly property string gpuKey: Model.gpuId(device)
      readonly property bool awake: device.asleep !== true
      readonly property var utilHistory: root.hist.gpus && root.hist.gpus[gpuKey] || []
      readonly property var tempHistory: root.hist.gpuTemps && root.hist.gpuTemps[gpuKey] || []
      readonly property var vramHistory: root.hist.vrams && root.hist.vrams[gpuKey] || []
      readonly property bool showTemps: Model.hasReading(tempHistory)
      readonly property bool showVram: Model.hasReading(vramHistory)
      foreground: root.foreground

      CardHeader {
        title: Model.gpuIcon(gpuCard.device.vendor) + "  " + Model.shortGpuName(gpuCard.device.name)
        detail: gpuCard.awake ? root.headerDetail(gpuCard.device) : "Asleep"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      HistoryGraph {
        visible: Model.hasReading(gpuCard.utilHistory)
        width: parent.width
        height: Commons.Style.space(56)
        barWidth: Model.historyBarWidth(width, root.historyRange)
        showGaps: root.historyRange > 0
        series: [gpuCard.utilHistory]
        colors: [gpuCard.seriesColor]
        sampleColors: [Model.utilizationHistoryColors(gpuCard.utilHistory, root.settings, root.lightTheme)]
        ceiling: 100
        baselineColor: Commons.Util.alpha(root.foreground, 0.14)
      }

      SectionTitle {
        visible: gpuCard.showTemps
        text: "Temperature"
        fontFamily: root.fontFamily
      }
      HistoryGraph {
        visible: gpuCard.showTemps
        width: parent.width
        height: Commons.Style.space(44)
        barWidth: Model.historyBarWidth(width, root.historyRange)
        showGaps: root.historyRange > 0
        series: [gpuCard.tempHistory]
        colors: [gpuCard.seriesColor]
        minimumCeiling: Model.TEMPERATURE_SCALE_FLOOR
        baselineColor: Commons.Util.alpha(root.foreground, 0.14)
      }

      SectionTitle {
        visible: gpuCard.showVram
        text: "VRAM usage"
        fontFamily: root.fontFamily
      }
      HistoryGraph {
        visible: gpuCard.showVram
        width: parent.width
        height: Commons.Style.space(44)
        barWidth: Model.historyBarWidth(width, root.historyRange)
        showGaps: root.historyRange > 0
        series: [gpuCard.vramHistory]
        colors: [gpuCard.seriesColor]
        sampleColors: [Model.utilizationHistoryColors(gpuCard.vramHistory, root.settings, root.lightTheme)]
        ceiling: 100
        baselineColor: Commons.Util.alpha(root.foreground, 0.14)
      }

      StatRow {
        visible: gpuCard.awake
        label: "Utilization"
        dot: gpuCard.seriesColor
        value: gpuCard.device.util !== null && isFinite(Number(gpuCard.device.util)) ? String(Math.round(gpuCard.device.util)) : "—"
        unit: gpuCard.device.util !== null && isFinite(Number(gpuCard.device.util)) ? "%" : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      StatRow {
        visible: gpuCard.device.temp !== null && isFinite(Number(gpuCard.device.temp))
        label: "Temperature"
        value: visible ? Model.tempParts(gpuCard.device.temp, root.temperatureUnit).value : ""
        unit: "°"
        valueColor: root.tempTextColor(gpuCard.device.temp)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      StatRow {
        visible: gpuCard.device.memTotal > 0
        label: "Memory"
        detail: visible ? Model.percentText(gpuCard.device.memUsed / gpuCard.device.memTotal * 100) : ""
        value: visible ? Model.pairText(gpuCard.device.memUsed, gpuCard.device.memTotal).replace(/ [A-Z]+$/, "") : ""
        unit: visible ? Units.bytesParts(gpuCard.device.memTotal).unit : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      StatRow {
        visible: gpuCard.device.power !== null && isFinite(Number(gpuCard.device.power))
        label: "Power"
        value: visible ? String(Math.round(gpuCard.device.power)) : ""
        unit: "W"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      ProcessList {
        visible: Model.flag(root.settings, "showProcesses") && gpuCard.awake
        expandable: false
        items: Array.isArray(gpuCard.device.procs) ? gpuCard.device.procs : []
        columns: [
          { key: "util", kind: "percent", title: "Load" },
          { key: "mem", kind: "bytes", title: gpuCard.device.integrated ? "Memory" : "VRAM" }
        ]
        emptyText: Array.isArray(gpuCard.device.procs) ? "Nothing using this GPU" : "Measuring…"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }
  }
}

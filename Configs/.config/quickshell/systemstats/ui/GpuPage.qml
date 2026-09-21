pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui as Ui
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

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var hist: service ? service.history : Model.emptyHistory()
  readonly property var gpu: snap.gpu || null
  readonly property var devices: gpu && Array.isArray(gpu.devices) ? gpu.devices : []

  function headerDetail(device) {
    var parts = []
    var frequency = Model.freqText(device.mhz)
    if (frequency) parts.push(frequency)
    if (device.temp !== null && isFinite(Number(device.temp))) parts.push(Model.tempText(device.temp, temperatureUnit))
    return parts.join(", ")
  }

  function graphColor(index) {
    if (!service) return Color.accent
    return index % 2 ? service.series2 : service.series1
  }

  function tempTextColor(celsius) {
    return Model.flag(settings, "colorTemperatureIcons") && service
      ? Model.temperatureColor(service.temperatureRamp, celsius, 100, foreground) : foreground
  }

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  Card {
    visible: root.devices.length > 1
    foreground: root.foreground

    SectionTitle { text: "Activity source"; fontFamily: root.fontFamily }

    Repeater {
      model: root.devices.length

      delegate: Ui.Button {
        required property int index
        readonly property var device: root.devices[index] || ({})
        readonly property bool active: device.active === true
        width: parent.width
        text: (active ? "Selected · " : "Select · ") + Model.gpuIcon(device.vendor) + "  " + Model.shortGpuName(device.name)
        selected: active
        bordered: true
        foreground: root.foreground
        accent: Color.accent
        fontFamily: root.fontFamily
        onClicked: if (!active && root.service) root.service.selectGpu(device.vendor)
      }
    }
  }

  Repeater {
    model: root.devices.length

    delegate: Card {
      id: gpuCard
      required property int index
      readonly property var device: root.devices[index] || ({})
      readonly property color seriesColor: root.graphColor(index)
      foreground: root.foreground

      CardHeader {
        title: Model.gpuIcon(gpuCard.device.vendor) + "  " + Model.shortGpuName(gpuCard.device.name)
        detail: root.headerDetail(gpuCard.device)
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      HistoryGraph {
        width: parent.width
        height: Style.space(56)
        series: [root.hist.gpus && root.hist.gpus[gpuCard.device.vendor] || []]
        colors: [gpuCard.seriesColor]
        ceiling: 100
        baselineColor: Util.alpha(root.foreground, 0.14)
      }

      StatRow {
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
        unit: visible ? Model.bytesParts(gpuCard.device.memTotal).unit : ""
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

    }
  }
}

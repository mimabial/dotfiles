pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property int historyRange: 0
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  function flag(key) { return Model.flag(settings, key) }

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var hist: service ? Model.peakHistoryView(service.history, service.historyHour, service.historyDay, historyRange) : Model.emptyHistory()
  readonly property color s1: service ? service.series1 : Color.accent
  readonly property color s2: service ? service.series2 : Color.accent
  readonly property color warn: service ? service.warn : Color.urgent
  readonly property color danger: service ? service.danger : Color.urgent

  readonly property var cpu: snap.cpu || ({})
  readonly property var gpu: snap.gpu || null
  readonly property var sensors: snap.sensors || ({})
  readonly property var temps: sortedTemps(Array.isArray(sensors.temps) ? sensors.temps : [])
  readonly property var fans: Array.isArray(sensors.fans) ? sensors.fans : []
  readonly property real cpuTemp: Model.num(cpu.temp, NaN)
  readonly property real gpuTemp: gpu && gpu.temp !== null && isFinite(Number(gpu.temp))
    ? Number(gpu.temp)
    : Model.num(sensors.gpuTemp, NaN)
  readonly property var fanSummary: {
    var active = 0
    var sum = 0
    var peak = 0
    for (var i = 0; i < fans.length; i++) {
      var rpm = Model.num(fans[i].rpm)
      if (rpm > 0) { active += 1; sum += rpm; peak = Math.max(peak, rpm) }
    }
    return { active: active, average: active > 0 ? sum / active : 0, peak: peak }
  }

  function chipRank(chip) {
    var order = ["CPU", "GPU", "NVMe", "Drive", "Memory", "Board", "Ethernet", "Wi-Fi", "ACPI"]
    var base = String(chip || "").replace(/\s\d+$/, "")
    var idx = order.indexOf(base)
    return idx < 0 ? order.length : idx
  }

  function sortedTemps(list) {
    var copy = list.slice()
    copy.sort(function(a, b) {
      var rankA = chipRank(a.chip), rankB = chipRank(b.chip)
      if (rankA !== rankB) return rankA - rankB
      return String(a.label).localeCompare(String(b.label))
    })
    return copy
  }

  function tempColor(celsius, max) {
    var limit = max > 0 ? max : Model.SENSOR_FALLBACK_CRITICAL
    var frac = Model.num(celsius) / limit
    if (frac >= Model.SENSOR_DANGER) return danger
    if (frac >= Model.SENSOR_WARN) return warn
    return s1
  }

  function tempTextColor(celsius, critical) {
    return flag("colorTemperatureIcons") && service
      ? Model.temperatureColor(service.temperatureRamp, celsius, critical, foreground) : foreground
  }

  function fraction(celsius, max) {
    var limit = max > 0 ? max : 100
    return Math.max(0, Math.min(1, Model.num(celsius) / limit))
  }

  function displayLabel(temp) { return Model.sensorLabel(temp) }

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  Card {
    foreground: root.foreground

    Item {
      width: parent.width
      height: rings.implicitHeight

      Row {
        id: rings
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(18)

        RingGauge {
          visible: isFinite(root.cpuTemp)
          value: root.fraction(root.cpuTemp, 100)
          color: root.tempColor(root.cpuTemp, 95)
          valueColor: root.tempTextColor(root.cpuTemp, 100)
          foreground: root.foreground
          fontFamily: root.fontFamily
          topText: "CPU"
          valueText: Model.tempParts(root.cpuTemp, root.temperatureUnit).value
          unitText: "°"
          subText: Model.freqText(root.cpu.mhz)
          valueSize: Style.font.heading
          size: Style.space(84)
        }

        RingGauge {
          visible: isFinite(root.gpuTemp)
          value: root.fraction(root.gpuTemp, 100)
          color: root.tempColor(root.gpuTemp, 90)
          valueColor: root.tempTextColor(root.gpuTemp, 100)
          foreground: root.foreground
          fontFamily: root.fontFamily
          topText: "GPU"
          valueText: Model.tempParts(root.gpuTemp, root.temperatureUnit).value
          unitText: "°"
          subText: root.gpu ? Model.freqText(root.gpu.mhz) : ""
          valueSize: Style.font.heading
          size: Style.space(84)
        }

        RingGauge {
          visible: root.fans.length > 0
          value: root.fanSummary.active > 0 ? Math.min(1, root.fanSummary.average / Model.FAN_FULL_SCALE_RPM) : 0
          color: root.s2
          foreground: root.foreground
          fontFamily: root.fontFamily
          topText: "Fans"
          valueText: root.fanSummary.active > 0 ? String(Math.round(root.fanSummary.average)) : "Off"
          unitText: root.fanSummary.active > 0 ? "rpm" : ""
          subText: root.fanSummary.active > 0 ? root.fanSummary.active + " of " + root.fans.length + " on" : ""
          valueSize: root.fanSummary.active > 0 ? Style.font.heading : Style.font.title
          size: Style.space(84)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: !isFinite(root.cpuTemp) && !isFinite(root.gpuTemp) && root.fans.length === 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "No hardware sensors found"
      color: root.foreground
      opacity: Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Card {
    visible: Model.hasReading(root.hist.cpuTemp) || Model.hasReading(root.hist.gpuTemp)
    foreground: root.foreground

    CardHeader { title: "Temperature history"; detail: "Peak in each time slot"; foreground: root.foreground; fontFamily: root.fontFamily }
    SectionTitle { visible: Model.hasReading(root.hist.cpuTemp); text: "CPU"; fontFamily: root.fontFamily }
    HistoryGraph {
      visible: Model.hasReading(root.hist.cpuTemp)
      width: parent.width
      height: Style.space(48)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.hist.cpuTemp || []]
      colors: [root.s1]
      minimumCeiling: Model.TEMPERATURE_SCALE_FLOOR
      baselineColor: Util.alpha(root.foreground, 0.14)
    }
    SectionTitle { visible: Model.hasReading(root.hist.gpuTemp); text: "GPU"; fontFamily: root.fontFamily }
    HistoryGraph {
      visible: Model.hasReading(root.hist.gpuTemp)
      width: parent.width
      height: Style.space(48)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.hist.gpuTemp || []]
      colors: [root.s2]
      minimumCeiling: Model.TEMPERATURE_SCALE_FLOOR
      baselineColor: Util.alpha(root.foreground, 0.14)
    }
  }

  Card {
    visible: root.temps.length > 0 && root.flag("showTemperatures")
    foreground: root.foreground
    spacing: Style.space(2)

    SectionTitle { text: "Temperature"; fontFamily: root.fontFamily }

    Repeater {
      model: root.temps.length

      delegate: Column {
        id: sensorRow
        required property int index
        readonly property var modelData: root.temps[index] || ({})
        readonly property string sensorId: String(modelData.alertId || "")
        readonly property real threshold: root.service ? root.service.sensorThreshold(sensorId) : -1
        width: parent.width
        spacing: Style.space(2)

        StatRow {
          width: parent.width
          label: root.displayLabel(sensorRow.modelData)
          value: Model.tempParts(sensorRow.modelData.value, root.temperatureUnit).value
          unit: "°"
          boldValue: false
          valueColor: sensorRow.threshold >= 0 && sensorRow.modelData.value >= sensorRow.threshold
            ? root.danger : root.tempTextColor(sensorRow.modelData.value, sensorRow.modelData.critical)
          foreground: root.foreground
          fontFamily: root.fontFamily
          ringValue: root.fraction(sensorRow.modelData.value, sensorRow.modelData.max)
          ringColor: sensorRow.threshold >= 0 && sensorRow.modelData.value >= sensorRow.threshold
            ? root.danger : root.tempColor(sensorRow.modelData.value, sensorRow.modelData.max)
        }

        Row {
          x: Style.space(8)
          spacing: Style.space(5)

          PanelActionButton {
            iconText: sensorRow.threshold < 0 ? "󰂚" : "󰂛"
            tooltipText: sensorRow.threshold < 0 ? "Enable temperature alert" : "Disable temperature alert"
            enabled: !!sensorRow.sensorId
            foreground: root.foreground
            fontFamily: root.fontFamily
            size: Style.space(20)
            onClicked: root.service.setSensorThreshold(sensorRow.sensorId, sensorRow.threshold < 0
              ? Math.max(Model.SENSOR_ALERT_MIN, Math.min(Model.SENSOR_ALERT_MAX, Math.ceil((Number(sensorRow.modelData.value) + 2 * Model.SENSOR_ALERT_STEP) / Model.SENSOR_ALERT_STEP) * Model.SENSOR_ALERT_STEP)) : null)
          }

          PanelActionButton {
            visible: sensorRow.threshold >= 0
            iconText: "−"
            enabled: sensorRow.threshold > Model.SENSOR_ALERT_MIN
            foreground: root.foreground
            fontFamily: root.fontFamily
            size: Style.space(20)
            onClicked: root.service.setSensorThreshold(sensorRow.sensorId, sensorRow.threshold - Model.SENSOR_ALERT_STEP)
          }

          Text {
            text: sensorRow.threshold < 0 ? "Alert off" : "Alert at " + sensorRow.threshold + "°C"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: sensorRow.threshold < 0 ? 0.45 : 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            height: Style.space(20)
            verticalAlignment: Text.AlignVCenter
          }

          PanelActionButton {
            visible: sensorRow.threshold >= 0
            iconText: "+"
            enabled: sensorRow.threshold < Model.SENSOR_ALERT_MAX
            foreground: root.foreground
            fontFamily: root.fontFamily
            size: Style.space(20)
            onClicked: root.service.setSensorThreshold(sensorRow.sensorId, sensorRow.threshold + Model.SENSOR_ALERT_STEP)
          }
        }
      }
    }
  }

  Card {
    visible: root.fans.length > 0 && root.flag("showFans")
    foreground: root.foreground
    spacing: Style.space(2)

    SectionTitle { text: "Fans"; fontFamily: root.fontFamily }

    Repeater {
      model: root.fans.length

      delegate: StatRow {
        id: fanRow
        required property int index
        readonly property var modelData: root.fans[index] || ({})
        readonly property real rpm: Model.num(modelData.rpm)
        label: String(modelData.label || "Fan")
        value: rpm > 0 ? String(Math.round(rpm)) : "Off"
        unit: rpm > 0 ? "rpm" : ""
        boldValue: false
        labelOpacity: rpm > 0 ? 0.85 : 0.5
        foreground: root.foreground
        fontFamily: root.fontFamily
        ringValue: Math.min(1, fanRow.rpm / Model.FAN_FULL_SCALE_RPM)
        ringColor: root.s2
      }
    }
  }
}

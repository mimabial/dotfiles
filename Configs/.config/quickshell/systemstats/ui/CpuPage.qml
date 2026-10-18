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

  function flag(key) { return Model.flag(settings, key) }

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var hist: service ? Model.peakHistoryView(service.history, service.historyHour, service.historyDay, historyRange) : Model.emptyHistory()
  readonly property color s1: service ? service.series1 : Commons.Color.accent
  readonly property color s2: service ? service.series2 : Commons.Color.accent
  readonly property var cpu: snap.cpu || ({})
  readonly property var procs: snap.procs || null
  readonly property var cores: Array.isArray(cpu.cores) ? cpu.cores : []
  readonly property var efficiency: Array.isArray(cpu.efficiency) ? cpu.efficiency : []
  readonly property bool hybrid: efficiency.length > 0 && efficiency.length < cores.length

  function headerDetail(mhz, temp) {
    var parts = []
    var freq = Model.freqText(mhz)
    if (freq) parts.push(freq)
    if (isFinite(Number(temp)) && temp !== null) parts.push(Model.tempText(temp, temperatureUnit))
    return parts.join(", ")
  }

  width: parent ? parent.width : implicitWidth
  spacing: Commons.Style.space(10)

  Card {
    foreground: root.foreground

    CardHeader {
      title: "CPU"
      detail: root.headerDetail(root.cpu.mhz, root.cpu.temp)
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    HistoryGraph {
      width: parent.width
      height: Commons.Style.space(64)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: root.historyRange === 0
        ? [root.hist.cpuUser || [], root.hist.cpuSystem || []]
        : [root.hist.cpuTotal || []]
      colors: root.historyRange === 0 ? [root.s1, root.s2] : [root.s1]
      ceiling: 100
      baselineColor: Commons.Util.alpha(root.foreground, 0.14)
    }

    Legend {
      foreground: root.foreground
      fontFamily: root.fontFamily
      items: root.historyRange === 0 ? [
        { color: root.s1, label: "User", value: Math.round(Model.num(root.cpu.user)), unit: "%" },
        { color: root.s2, label: "System", value: Math.round(Model.num(root.cpu.system)), unit: "%" }
      ] : [
        { color: root.s1, label: "Peak CPU", value: Math.round(Model.maxOf(root.hist.cpuTotal)), unit: "%" }
      ]
    }

    SectionTitle {
      visible: Model.hasReading(root.hist.cpuTemp)
      text: "CPU temperature · " + Model.tempText(root.cpu.temp, root.temperatureUnit)
      fontFamily: root.fontFamily
    }

    HistoryGraph {
      visible: Model.hasReading(root.hist.cpuTemp)
      width: parent.width
      height: Commons.Style.space(48)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      series: [root.hist.cpuTemp || []]
      colors: [root.s2]
      minimumCeiling: Model.TEMPERATURE_SCALE_FLOOR
      baselineColor: Commons.Util.alpha(root.foreground, 0.14)
    }
  }

  Card {
    visible: root.flag("showCores")
    foreground: root.foreground
    spacing: Commons.Style.space(10)

    Flow {
      width: parent.width
      spacing: Commons.Style.space(6)

      Repeater {
        model: root.cores.length

        delegate: MiniRing {
          required property int index
          value: Model.num(root.cores[index]) / 100
          color: root.efficiency.indexOf(index) >= 0 ? root.s2 : root.s1
          foreground: root.foreground
          size: Commons.Style.space(18)
          thickness: Commons.Style.spaceReal(2.6)
        }
      }
    }

    Legend {
      foreground: root.foreground
      fontFamily: root.fontFamily
      items: root.hybrid
        ? [
            { color: root.s1, label: "Performance", value: root.cores.length - root.efficiency.length, unit: "" },
            { color: root.s2, label: "Efficiency", value: root.efficiency.length, unit: "" }
          ]
        : [
            { color: root.s1, label: "Cores", value: Model.num(root.cpu.coreCount), unit: "" },
            { color: Commons.Util.alpha(root.foreground, 0.25), label: "Threads", value: Model.num(root.cpu.threadCount), unit: "" }
          ]
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      text: String(root.cpu.model || "")
      color: root.foreground
      opacity: Commons.Style.faintTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      elide: Text.ElideRight
    }
  }

  Card {
    visible: root.flag("showLoad")
    foreground: root.foreground

    Row {
      width: parent.width

      Column {
        width: parent.width / 2
        spacing: Commons.Style.space(3)

        SectionTitle { text: "Load average"; fontFamily: root.fontFamily }

        Text {
          textFormat: Text.PlainText
          text: Model.loadText(root.cpu.load)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.body
          font.bold: true
        }
      }

      Column {
        width: parent.width / 2
        spacing: Commons.Style.space(3)

        SectionTitle { text: "Uptime"; fontFamily: root.fontFamily; anchors.right: parent.right }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          text: Units.spanText(root.cpu.uptime) || "<1m"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.body
          font.bold: true
        }
      }
    }
  }

  Card {
    visible: root.flag("showProcesses")
    foreground: root.foreground

    ProcessList {
      host: root.host
      items: root.procs ? (root.procs.cpu || []) : []
      allItems: root.procs ? (root.procs.all || []) : []
      total: root.procs ? Model.num(root.procs.total) : 0
      columns: [{ key: "cpu", kind: "percent", title: "" }]
      emptyText: root.procs ? "Nothing busy" : "Measuring…"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}

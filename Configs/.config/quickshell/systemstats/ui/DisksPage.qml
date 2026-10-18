pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
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
  readonly property color warn: service ? service.warn : Commons.Color.urgent
  readonly property color danger: service ? service.danger : Commons.Color.urgent

  readonly property var disks: snap.disks || ({})
  readonly property var volumes: Array.isArray(disks.volumes) ? disks.volumes : []
  readonly property var diskOptions: Model.diskOptions(snap)
  readonly property var procs: snap.procs || null
  readonly property string source: String(Model.settingValue(settings, "disksSource") || "all")
  readonly property bool singleDisk: source !== "all" && !!(disks.perDisk && disks.perDisk[source])
  readonly property real readRate: singleDisk ? Model.num(disks.perDisk[source].read) : Model.num(disks.read)
  readonly property real writeRate: singleDisk ? Model.num(disks.perDisk[source].write) : Model.num(disks.write)
  readonly property var readHistory: singleDisk && hist.disks && hist.disks[source] ? hist.disks[source].read : (hist.diskRead || [])
  readonly property var writeHistory: singleDisk && hist.disks && hist.disks[source] ? hist.disks[source].write : (hist.diskWrite || [])
  readonly property var readParts: Model.rateParts(readRate)
  readonly property var writeParts: Model.rateParts(writeRate)
  readonly property string sourceModel: {
    if (!singleDisk) return ""
    for (var i = 0; i < volumes.length; i++) if (volumes[i].disk === source && volumes[i].model) return String(volumes[i].model)
    return ""
  }

  function openVolume(mount) {
    if (!mount) return
    Commons.Util.execArgv(["xdg-open", String(mount)])
    if (host && typeof host.close === "function") host.close()
  }

  function selectDisk(source) {
    if (host && typeof host.persist === "function") host.persist("disksSource", source)
  }

  width: parent ? parent.width : implicitWidth
  spacing: Commons.Style.space(10)

  Card {
    visible: root.diskOptions.length > 1
    foreground: root.foreground

    SectionTitle { text: "Activity source"; fontFamily: root.fontFamily }

    Repeater {
      model: root.diskOptions.length

      delegate: Ui.Button {
        required property int index
        readonly property var option: root.diskOptions[index] || ({})
        readonly property bool active: String(option.value) === root.source
        width: parent.width
        text: (active ? "Selected · " : "Select · ") + String(option.label || "")
        selected: active
        bordered: true
        foreground: root.foreground
        accent: Commons.Color.accent
        fontFamily: root.fontFamily
        onClicked: if (!active) root.selectDisk(String(option.value))
      }
    }
  }

  Card {
    visible: root.flag("showVolumes")
    foreground: root.foreground
    spacing: Commons.Style.space(4)

    SectionTitle { text: "Volumes · open in files"; fontFamily: root.fontFamily }

    Text {
      textFormat: Text.PlainText
      visible: root.volumes.length === 0
      text: "No mounted volumes"
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.bodySmall
    }

    Repeater {
      model: root.volumes.length

      delegate: Item {
        id: row
        required property int index
        readonly property var modelData: root.volumes[index] || ({})
        readonly property real fraction: modelData.size > 0 ? modelData.used / modelData.size : 0
        readonly property string tempText: isFinite(Number(modelData.temp)) && modelData.temp !== null
          ? Model.tempText(modelData.temp, root.temperatureUnit) : ""

        width: parent.width
        height: Commons.Style.space(34)

        MiniRing {
          id: ring
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          size: Commons.Style.space(24)
          thickness: Commons.Style.spaceReal(3)
          value: row.fraction
          color: row.fraction >= Model.DISK_DANGER ? root.danger : (row.fraction >= Model.DISK_WARN ? root.warn : root.s1)
          foreground: root.foreground
        }

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: ring
          text: Math.round(row.fraction * 100)
          color: root.foreground
          opacity: Commons.Style.secondaryTextAlpha
          font.family: root.fontFamily
          font.pixelSize: Math.max(7, Commons.Style.font.caption - 2)
          font.bold: true
        }

        Column {
          anchors.left: ring.right
          anchors.leftMargin: Commons.Style.space(10)
          anchors.right: trailing.left
          anchors.rightMargin: Commons.Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: Model.volumeName(row.modelData.mount)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: Units.bytesText(row.modelData.avail) + " available"
            color: root.foreground
            opacity: Commons.Style.mutedTextAlpha
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.caption
            elide: Text.ElideRight
          }
        }

        Column {
          id: trailing
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Measure {
            anchors.right: parent.right
            value: Units.bytesParts(row.modelData.size).value
            unit: Units.bytesParts(row.modelData.size).unit
            foreground: root.foreground
            fontFamily: root.fontFamily
            bold: false
            valueOpacity: 0.85
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: [row.modelData.fstype, row.tempText].filter(function(v) { return !!v }).join(" · ")
            color: root.foreground
            opacity: Commons.Style.faintTextAlpha
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.caption
          }
        }

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openVolume(row.modelData.mount)
        }

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -Commons.Style.space(6)
          anchors.rightMargin: -Commons.Style.space(6)
          z: -1
          radius: Commons.Style.cornerRadius
          color: hover.containsMouse ? Commons.Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
        }

      }
    }
  }

  Card {
    visible: root.flag("showActivity")
    foreground: root.foreground

    CardHeader {
      title: "Activity"
      detail: root.singleDisk ? root.source + (root.sourceModel ? " · " + root.sourceModel : "") : "All disks"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      width: parent.width

      BigStat {
        width: parent.width / 2
        value: root.readParts.value
        unit: root.readParts.unit
        label: "Read"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      BigStat {
        width: parent.width / 2
        value: root.writeParts.value
        unit: root.writeParts.unit
        label: "Write"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    MirrorGraph {
      id: graph
      width: parent.width
      height: Commons.Style.space(72)
      barWidth: Model.historyBarWidth(width, root.historyRange)
      showGaps: root.historyRange > 0
      up: root.readHistory
      down: root.writeHistory
      upColor: root.s2
      downColor: root.s1
      minimumCeiling: Model.DISK_SCALE_FLOOR
      midlineColor: Commons.Util.alpha(root.foreground, 0.18)
    }

    Legend {
      foreground: root.foreground
      fontFamily: root.fontFamily
      items: [
        { color: root.s2, label: "Read peak", value: Model.rateParts(graph.peakUp).value, unit: Model.rateParts(graph.peakUp).unit },
        { color: root.s1, label: "Write peak", value: Model.rateParts(graph.peakDown).value, unit: Model.rateParts(graph.peakDown).unit }
      ]
    }
  }

  Card {
    visible: root.flag("showProcesses")
    foreground: root.foreground

    ProcessList {
      host: root.host
      items: root.procs ? (root.procs.io || []) : []
      allItems: root.procs ? (root.procs.all || []) : []
      total: root.procs ? Model.num(root.procs.total) : 0
      sortKey: "io"
      columns: [
        { key: "read", kind: "rate", title: "Read" },
        { key: "write", kind: "rate", title: "Write" }
      ]
      columnWidth: Commons.Style.space(70)
      emptyText: root.procs ? "No disk activity" : "Measuring…"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}

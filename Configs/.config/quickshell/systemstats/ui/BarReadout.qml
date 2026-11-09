pragma ComponentBehavior: Bound

import QtQuick
import qs as Bar
import qs.Commons as Commons
import "../Model.js" as Model

Item {
  id: root

  required property var shell
  property int barSize: Commons.Style.bar.sizeHorizontal
  property string fontFamily: shell.fontFamily
  required property var box
  readonly property real iconSize: Commons.Style.fontPx(box.fontSize) * shell.iconFontScale
  readonly property color foreground: shell.styleColor(box.color, shell.foreground)
  property real horizontalMargin
  property real fixedWidth
  property real fixedHeight
  property bool labelVisible
  property bool hasVisualContent
  property string text
  property string module: "cpu"
  property var service: null
  property string mode: "both"
  property int graphWidth: 36
  property string temperatureUnit: "Celsius"
  property bool colorTemperatureIcons: true
  // Disks: "all" or a block device name. Sensors: comma list of sensor ids.
  property string disksSource: "all"
  property string diskShow: "speed"
  property string barSensors: "cpu"
  property string gpuId: ""
  property string shortLabel: ""
  property var settings: ({})
  property string labelMode: "text"

  signal activated(string module, int button)
  signal pressed(int button)

  readonly property real scaledHorizontalMargin: Commons.Style.spaceReal(horizontalMargin)
  implicitWidth: fixedWidth > 0 ? fixedWidth : content.implicitWidth + scaledHorizontalMargin * 2
  implicitHeight: fixedHeight > 0 ? fixedHeight : barSize
  visible: hasVisualContent

  readonly property var snap: service ? service.snapshot : ({})
  readonly property var hist: service ? service.history : ({})
  readonly property bool isGpuMemory: module === "gpuMemory"
  readonly property var def: Model.moduleDef(isGpuMemory ? "gpu" : module)
  readonly property string label: shortLabel || def.short || def.label
  readonly property bool ready: !!(service && service.ready)
  readonly property bool gpuMeasured: isGpuMemory ? gpuMemoryPercent !== null : Model.gpuHasUtil(gpu)
  readonly property bool isGpu: module === "gpu" || isGpuMemory
  readonly property bool isDisk: module === "disks"
  readonly property bool diskSpeed: diskShow !== "used"
  readonly property bool diskUsed: diskShow !== "speed"
  readonly property bool ringable: def.ring === true
  readonly property bool graphable: def.graph === true
  readonly property bool pictured: mode !== "text" && (!isGpu || gpuMeasured)
  readonly property bool figured: mode !== "graph" && mode !== "ring"
  readonly property bool showGraph: graphable && pictured && (isDisk ? diskSpeed : mode === "both" || mode === "graph")
  readonly property bool showRing: ringable && pictured && (isDisk ? diskUsed : mode === "ring" || mode === "ring-text")
  readonly property bool showText: isDisk ? figured && diskUsed
    : mode === "both" || mode === "text" || mode === "ring-text" || (!graphable && !ringable) || (isGpu && !gpuMeasured)
  readonly property bool showRates: isDisk && figured && diskSpeed
  readonly property bool twoLine: module === "network" || isDisk
  readonly property bool hovered: pointer.containsMouse
  readonly property color contentColor: hovered ? shell.role("hvr_fg", foreground) : foreground
  readonly property color s1: hovered ? contentColor : (service ? service.series1 : foreground)
  readonly property color s2: hovered ? contentColor : (service ? service.series2 : foreground)
  readonly property real graphHeight: labelMode === "text" && module !== "sensors" && stackLabel.height > 0
    ? stackLabel.height : Math.max(8, barSize - Commons.Style.space(11))
  readonly property bool lightTheme: shell.background.hslLightness > 0.5
  readonly property real utilizationPercent: module === "cpu" ? Model.num(cpu.total, NaN)
    : isGpu ? (gpuMeasured ? ringValue * 100 : NaN)
    : module === "memory" ? (mem.total > 0 ? memPercent : NaN)
    : isDisk && diskUsed && diskUsage.size > 0 ? ringValue * 100 : NaN
  readonly property color utilizationColor: hovered ? contentColor : Model.utilizationColor(settings, utilizationPercent, lightTheme) || Qt.color("transparent")
  readonly property bool graded: utilizationColor.a > 0

  readonly property var cpu: snap.cpu || ({})
  readonly property var gpu: Model.gpuById(snap, gpuId) || Model.gpuList(snap)[0] || null
  readonly property var gpuMemoryPercent: Model.gpuMemoryPercent(gpu)
  readonly property var mem: snap.mem || ({})
  readonly property var net: snap.net || ({})
  readonly property var disks: snap.disks || ({})
  readonly property var sensors: snap.sensors || ({})
  readonly property var battery: snap.battery || null

  readonly property real memPercent: mem.total > 0 ? mem.used / mem.total * 100 : 0
  readonly property bool charging: !!(battery && (battery.status === "Charging" || battery.status === "Full"))
  readonly property bool batteryPercentKnown: !!(battery && battery.percent !== null && battery.percent !== undefined && isFinite(Number(battery.percent)))

  readonly property bool singleDisk: disksSource !== "all" && !!(disks.perDisk && disks.perDisk[disksSource])
  readonly property var diskUsage: Model.diskUsage(snap, singleDisk ? disksSource : "all")
  readonly property real diskRead: singleDisk ? Model.num(disks.perDisk[disksSource].read) : Model.num(disks.read)
  readonly property real diskWrite: singleDisk ? Model.num(disks.perDisk[disksSource].write) : Model.num(disks.write)
  readonly property var diskReadHistory: singleDisk && hist.disks && hist.disks[disksSource] ? hist.disks[disksSource].read : (hist.diskRead || [])
  readonly property var diskWriteHistory: singleDisk && hist.disks && hist.disks[disksSource] ? hist.disks[disksSource].write : (hist.diskWrite || [])
  readonly property var gpuHistory: gpu && ((isGpuMemory ? hist.vrams : hist.gpus) || {})[Model.gpuId(gpu)] || []

  readonly property real ringValue: {
    switch (module) {
      case "cpu": return Model.num(cpu.total) / 100
      case "gpu": return gpuMeasured ? Model.num(gpu.util) / 100 : 0
      case "gpuMemory": return gpuMeasured ? gpuMemoryPercent / 100 : 0
      case "memory": return memPercent / 100
      case "battery": return batteryPercentKnown ? Model.num(battery.percent) / 100 : 0
      case "disks": return diskUsage.fraction
    }
    return 0
  }
  readonly property color ringColor: {
    if (hovered) return contentColor
    if (module === "battery") return battery && charging ? (service ? service.good : s1) : (ringValue <= Model.BATTERY_CRITICAL_PERCENT / 100 ? (service ? service.danger : s1) : s1)
    if (graded) return utilizationColor
    if (module === "disks") return ringValue >= Model.DISK_DANGER ? (service ? service.danger : s1) : (ringValue >= Model.DISK_WARN ? (service ? service.warn : s1) : s1)
    return s1
  }

  function temperatureColor(celsius, critical) {
    if (!colorTemperatureIcons || !service) return foreground
    return Qt.alpha(Model.temperatureColor(service.temperatureRamp, celsius, critical, foreground), foreground.a)
  }

  function rateLabel(prefix, value) { return prefix + " " + Model.compactRate(value) }

  readonly property var sensorReadings: {
    var ids = Model.parseList(barSensors)
    var out = []
    for (var sensorId of ids) {
      var reading = Model.sensorReading(snap, sensorId, temperatureUnit)
      if (reading) out.push(reading)
    }
    return out
  }

  readonly property string glyph: module === "battery" && batteryPercentKnown ? Model.batteryIcon(battery.percent, charging)
    : isGpuMemory ? Model.moduleDef("memory").icon
    : module === "gpu" && gpu ? Model.gpuIcon(gpu.vendor) : def.icon
  readonly property var gpuTemperature: gpu && gpu.temp !== null && isFinite(Number(gpu.temp)) ? gpu.temp
    : sensors.gpuTemp !== null && isFinite(Number(sensors.gpuTemp)) ? sensors.gpuTemp : cpu.temp
  readonly property color glyphColor: hovered ? contentColor
    : module === "cpu" ? temperatureColor(cpu.temp)
    : module === "gpu" && gpu ? temperatureColor(gpuTemperature) : foreground
  readonly property color metricColor: graded ? utilizationColor : module === "cpu" || module === "gpu" ? glyphColor : contentColor

  readonly property string primaryText: {
    if (!ready) return "…"
    switch (module) {
      case "cpu": return Model.percentText(cpu.total)
      case "gpu": return gpuMeasured ? Model.percentText(gpu.util) : gpu && gpu.asleep ? "Off" : gpu ? Model.compactFreq(gpu.mhz) : "—"
      case "gpuMemory": return gpuMeasured ? Model.percentText(gpuMemoryPercent) : "—"
      case "memory": return Model.percentText(memPercent)
      case "battery": return batteryPercentKnown ? Model.percentText(battery.percent) : "—"
      case "network": return rateLabel("↑", net.tx)
      case "disks": return rateLabel("R", diskRead)
    }
    return ""
  }

  readonly property string secondaryText: {
    if (!ready) return "…"
    if (module === "network") return rateLabel("↓", net.rx)
    if (module === "disks") return rateLabel("W", diskWrite)
    return ""
  }

  readonly property string reserveText: {
    switch (module) {
      case "network":
      case "disks": return "↓ 999K"
      default: return "100%"
    }
  }

  labelVisible: false
  hasVisualContent: module !== "sensors" || sensorReadings.length > 0
  text: def.icon
  horizontalMargin: 5
  fixedWidth: content.implicitWidth + scaledHorizontalMargin * 2
  fixedHeight: -1
  onPressed: function(button) { root.activated(root.module, button) }

  TextMetrics {
    id: reserve
    font.family: root.fontFamily
    font.pixelSize: root.twoLine ? Commons.Style.font.caption : Commons.Style.font.body
    text: root.reserveText
  }

  Grid {
    id: content
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    columns: 0
    rows: 1
    spacing: Commons.Style.space(4)
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    ReadoutIcon {
      visible: root.module !== "sensors" && root.labelMode === "icon"
      glyph: root.glyph
      color: root.glyphColor
    }

    StackLabel {
      id: stackLabel
      visible: root.module !== "sensors" && root.labelMode === "text"
      text: root.label
      color: root.metricColor
      fontFamily: root.fontFamily
      letterSize: Commons.Style.spaceReal(10)
      maxHeight: root.barSize - Commons.Style.space(3)
    }

    Text {
      visible: root.module !== "sensors" && root.labelMode === "inline"
      textFormat: Text.PlainText
      text: root.label
      color: root.metricColor
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      renderType: Text.NativeRendering
    }

    Loader {
      active: root.showGraph && root.module !== "sensors"
      visible: active
      sourceComponent: root.twoLine ? mirrorGraph : historyGraph
    }

    Loader {
      active: root.showRates
      visible: active
      sourceComponent: twoLineText
    }

    Loader {
      active: root.showRing
      visible: active
      sourceComponent: ringGauge
    }

    Loader {
      active: root.showText && root.module !== "sensors"
      visible: active
      sourceComponent: root.module === "network" ? twoLineText : singleText
    }

    Repeater {
      model: root.module === "sensors" ? root.sensorReadings.length : 0

      delegate: Grid {
        id: sensorPair
        required property int index
        readonly property var reading: root.sensorReadings[index] || ({})
        readonly property string unitSuffix: String(reading.unit || "")
        readonly property color readingColor: root.hovered ? root.contentColor : root.temperatureColor(reading.celsius, reading.critical)
        columns: 0
        rows: 1
        spacing: Commons.Style.space(3)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        ReadoutIcon {
          visible: root.labelMode === "icon"
          glyph: sensorPair.reading.icon || "󰔏"
          color: sensorPair.readingColor
        }

        StackLabel {
          visible: root.labelMode === "text"
          text: sensorPair.reading.short || "TMP"
          color: sensorPair.readingColor
          fontFamily: root.fontFamily
          letterSize: Commons.Style.spaceReal(10)
          maxHeight: root.barSize - Commons.Style.space(3)
        }

        TextMetrics {
          id: sensorReserve
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.body
          text: "100" + sensorPair.unitSuffix
        }

        Text {
          textFormat: Text.PlainText
          width: Math.ceil(sensorReserve.advanceWidth)
          horizontalAlignment: Text.AlignRight
          text: root.ready ? String(sensorPair.reading.text || "") + sensorPair.unitSuffix : "…"
          color: sensorPair.readingColor
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.body
          renderType: Text.NativeRendering
        }
      }
    }
  }

  component ReadoutIcon: Item {
    id: readoutIcon
    required property string glyph
    required property color color
    readonly property string symbol: typeof root.box.symbol === "string" ? root.box.symbol : root.box.symbol?.[glyph] ?? ""
    implicitWidth: glyphText.implicitWidth; implicitHeight: glyphText.implicitHeight
    Loader {
      id: symbolic
      active: readoutIcon.visible && readoutIcon.symbol !== ""; anchors.centerIn: parent
      sourceComponent: Component { Bar.SymbolicIcon { name: readoutIcon.symbol; color: readoutIcon.color; size: Math.round(metrics.tightBoundingRect.height); directory: root.box.symbols ?? "" } }
    }
    Text {
      id: glyphText
      visible: !((symbolic.item as Bar.SymbolicIcon)?.loaded ?? false)
      textFormat: Text.PlainText; text: readoutIcon.glyph; color: readoutIcon.color
      font.family: root.shell.iconGlyphFont; font.pixelSize: root.iconSize; renderType: Text.NativeRendering
    }
    TextMetrics { id: metrics; text: glyphText.text; font: glyphText.font }
  }

  Component {
    id: ringGauge

    MiniRing {
      size: Math.max(10, root.barSize - Commons.Style.space(10))
      thickness: Commons.Style.spaceReal(2.4)
      value: root.ringValue
      color: root.ringColor
      foreground: root.contentColor
      trackColor: Commons.Util.scaleAlpha(root.contentColor, 0.22)
    }
  }

  Component {
    id: historyGraph

    HistoryGraph {
      width: root.graphWidth
      height: root.graphHeight
      barWidth: 1
      gap: 1
      ceiling: 100
      series: root.module === "cpu"
        ? [root.hist.cpuUser || [], root.hist.cpuSystem || []]
        : [root.module === "memory" ? (root.hist.memUsed || []) : root.gpuHistory]
      colors: root.isGpuMemory ? [root.s2] : [root.s1, root.s2]
      sampleColors: {
        if (root.hovered) return []
        var grades = Model.utilizationHistoryColors(root.module === "cpu" ? root.hist.cpuTotal : root.module === "memory" ? root.hist.memUsed : root.gpuHistory, root.settings, root.lightTheme)
        return root.module === "cpu" ? [grades, grades] : [grades]
      }
      baselineColor: Commons.Util.scaleAlpha(root.contentColor, 0.28)
    }
  }

  Component {
    id: mirrorGraph

    MirrorGraph {
      width: root.graphWidth
      height: root.graphHeight
      barWidth: 1
      gap: 1
      up: root.module === "network" ? (root.hist.netTx || []) : root.diskReadHistory
      down: root.module === "network" ? (root.hist.netRx || []) : root.diskWriteHistory
      upColor: root.s2
      downColor: root.s1
      minimumCeiling: root.module === "network" ? Model.NETWORK_SCALE_FLOOR : Model.DISK_SCALE_FLOOR
      midlineColor: Commons.Util.scaleAlpha(root.contentColor, 0.32)
    }
  }

  Component {
    id: singleText

    Text {
      textFormat: Text.PlainText
      width: Math.ceil(reserve.advanceWidth)
      horizontalAlignment: Text.AlignRight
      text: root.isDisk ? (root.ready ? Model.percentText(root.ringValue * 100) : "…") : root.primaryText
      color: root.metricColor
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      renderType: Text.NativeRendering
    }
  }

  Component {
    id: twoLineText

    Column {
      spacing: 0

      Text {
        textFormat: Text.PlainText
        width: Math.ceil(reserve.advanceWidth)
        horizontalAlignment: Text.AlignLeft
        text: root.primaryText
        color: root.contentColor
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        lineHeight: 0.95
        renderType: Text.NativeRendering
      }

      Text {
        textFormat: Text.PlainText
        width: Math.ceil(reserve.advanceWidth)
        horizontalAlignment: Text.AlignLeft
        text: root.secondaryText
        color: root.contentColor
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        lineHeight: 0.95
        renderType: Text.NativeRendering
      }
    }
  }

  MouseArea {
    id: pointer
    z: 10
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(event) { root.pressed(event.button) }
  }

}

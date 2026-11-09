pragma ComponentBehavior: Bound

import QtQuick
import qs as ShellUi
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model
import "../../Units.js" as Units

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family

  readonly property bool hasGpu: !!(service && service.hasGpu)
  readonly property bool hasBattery: !!(service && service.hasBattery)
  readonly property var barModules: Model.parseModules(Model.settingValue(settings, "modules"))
  readonly property var tabModules: Model.parseModules(Model.settingValue(settings, "tabs"))
  readonly property var availableModules: {
    var out = []
    for (var module of Model.MODULES) {
      var id = module.id
      if (id === "settings" || id === "alerts" || id === "power") continue
      if (id === "gpu" && !hasGpu) continue
      if (id === "battery" && !hasBattery) continue
      out.push(id)
    }
    return out
  }
  readonly property var orderedModules: {
    var out = []
    for (var barModule of barModules) if (availableModules.indexOf(barModule) !== -1) out.push(barModule)
    for (var availableModule of availableModules) if (out.indexOf(availableModule) === -1) out.push(availableModule)
    return out
  }
  readonly property var pages: {
    var out = []
    for (var id of Model.PANEL_TABS) {
      if (id === "gpu" && !hasGpu) continue
      if (id === "battery" && !hasBattery) continue
      out.push(id)
    }
    return out
  }
  readonly property var snapshot: service ? service.snapshot : ({})
  readonly property var diskOptions: Model.diskOptions(snapshot)
  readonly property var gpuOptions: Model.gpuList(snapshot)
  readonly property var selectedGpuIds: Model.selectedGpus(snapshot, Model.settingValue(settings, "barGpus")).map(Model.gpuId)
  readonly property var discreteGpuIds: Model.discreteGpus(snapshot).map(Model.gpuId)
  readonly property var barDiskList: Model.barDisksHere(snapshot, settings).map(function(entry) {
    return { disk: Model.stableDiskId(root.snapshot, entry.disk), show: entry.show }
  })
  readonly property var sensorOptions: Model.sensorOptions(snapshot)
  readonly property var barSensorIds: Model.parseList(Model.settingValue(settings, "barSensors"))
  readonly property bool lightTheme: foreground.hslLightness < 0.5
  property int focusedColorEditors: 0
  property var draggedRow: null
  property point dragPosition: Qt.point(0, 0)

  function gpuOrder(id) {
    var at = gpuOptions.findIndex(function(card) { return Model.gpuId(card) === id })
    return at === -1 ? gpuOptions.length : at
  }

  function setBarGpu(id, enabled) {
    var list = selectedGpuIds.filter(function(known) { return root.gpuOrder(known) < root.gpuOptions.length && known !== id })
    if (enabled) list.push(id)
    list.sort(function(a, b) { return root.gpuOrder(a) - root.gpuOrder(b) })
    if (list.length === 0) set("barGpus", "none")
    else if (list.length === gpuOptions.length) set("barGpus", "all")
    else if (list.join(",") === discreteGpuIds.join(",")) set("barGpus", "discrete")
    else set("barGpus", list.join(","))
  }

  function diskIndex(disk) {
    return barDiskList.findIndex(function(entry) { return entry.disk === disk })
  }

  function setBarDisk(disk, enabled, show) {
    var list = barDiskList.filter(function(entry) { return entry.disk !== disk })
    var at = diskIndex(disk)
    if (enabled) list.push({ disk: disk, show: show || (at === -1 ? "speed" : barDiskList[at].show) })
    var order = diskOptions.map(function(option) { return option.value })
    list.sort(function(a, b) { return order.indexOf(a.disk) - order.indexOf(b.disk) })
    set("barDisks", Model.barDisksText(list))
  }

  function setBarSensor(id, enabled) {
    var list = barSensorIds.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) list.push(id)
    if (!enabled && at !== -1) list.splice(at, 1)
    set("barSensors", list.join(","))
  }

  function set(key, value) {
    if (host && typeof host.persist === "function") host.persist(key, value)
  }

  function num(key) { return Number(Model.settingValue(settings, key)) }

  function setModuleEnabled(id, enabled) {
    var list = barModules.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) list.push(id)
    if (!enabled && at !== -1) list.splice(at, 1)
    set("modules", list.join(","))
  }

  function setTabEnabled(id, enabled) {
    var list = tabModules.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) {
      list.push(id)
      list.sort(function(a, b) { return Model.PANEL_TABS.indexOf(a) - Model.PANEL_TABS.indexOf(b) })
    }
    if (!enabled && at !== -1) list.splice(at, 1)
    set("tabs", list.join(","))
  }

  Item {
    id: dragMarker
    parent: root.Window.contentItem
    width: Commons.Style.spacing.hairline
    height: width
    x: root.dragPosition.x
    y: root.dragPosition.y
    Drag.source: root.draggedRow
    Drag.keys: ["systemstats-module"]
    Drag.proposedAction: Qt.MoveAction
  }

  width: parent ? parent.width : implicitWidth
  spacing: Commons.Style.space(10)
  Card {
    foreground: root.foreground
    spacing: Commons.Style.space(6)

    SectionTitle { text: "Bar"; fontFamily: root.fontFamily }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Drag a readout's handle to change the bar order. Each can show a mini graph, a figure, or both."
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.orderedModules.length

      delegate: DropArea {
        id: moduleRow
        required property int index
        readonly property string moduleId: String(root.orderedModules[index] || "")
        readonly property var def: Model.moduleDef(moduleId)
        readonly property int position: root.barModules.indexOf(moduleId)
        readonly property bool moduleEnabled: position !== -1

        width: parent.width
        height: moduleContent.implicitHeight
        keys: ["systemstats-module"]
        onEntered: drag => {
          if (drag.source !== root.draggedRow || !moduleEnabled || drag.source === moduleRow) drag.accepted = false
        }
        onDropped: drop => {
          if (drop.source !== root.draggedRow || !moduleEnabled || drop.source === moduleRow) return
          const from = root.barModules.indexOf(root.draggedRow.moduleId)
          const to = position + (drop.y >= height / 2 ? 1 : 0) - (from < position ? 1 : 0)
          const modules = Model.moveInList(root.barModules, root.draggedRow.moduleId, to - from).join(",")
          drop.acceptProposedAction()
          Qt.callLater(() => root.set("modules", modules))
        }

        Rectangle {
          z: 1
          visible: moduleRow.containsDrag
          width: parent.width
          height: Commons.Style.spacing.hairline
          y: moduleRow.drag.y >= moduleRow.height / 2 ? parent.height - height : 0
          color: Commons.Color.accent
        }

        Column {
          id: moduleContent
          width: parent.width
          spacing: Commons.Style.space(4)
          topPadding: Commons.Style.space(4)

          Item {
            width: parent.width
            height: Commons.Style.space(26)

            ShellUi.ToggleSwitch {
              id: moduleSwitch
              shell: root.host ? root.host.shell : null
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              checked: moduleRow.moduleEnabled
              onToggled: root.setModuleEnabled(moduleRow.moduleId, !moduleRow.moduleEnabled)
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: moduleSwitch.right
              anchors.leftMargin: Commons.Style.space(12)
              anchors.right: reorder.left
              anchors.rightMargin: Commons.Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: moduleRow.def.label
              color: root.foreground
              opacity: moduleRow.moduleEnabled ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.body
              font.bold: moduleRow.moduleEnabled
              elide: Text.ElideRight
            }

            Row {
              id: reorder
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Commons.Style.space(2)
              visible: moduleRow.moduleEnabled

              PanelActionButton {
                iconText: "󰁝"
                enabled: moduleRow.position > 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                size: Commons.Style.space(22)
                onClicked: root.set("modules", Model.moveInList(root.barModules, moduleRow.moduleId, -1).join(","))
              }

              PanelActionButton {
                iconText: "󰁅"
                enabled: moduleRow.position < root.barModules.length - 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                size: Commons.Style.space(22)
                onClicked: root.set("modules", Model.moveInList(root.barModules, moduleRow.moduleId, 1).join(","))
              }

              PanelActionButton {
                iconText: "⠿"
                tooltipText: "Drag to reorder"
                foreground: root.foreground
                fontFamily: root.fontFamily
                size: Commons.Style.space(22)
                focusable: false

                DragHandler {
                  target: null
                  enabled: moduleRow.moduleEnabled
                  cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  onActiveChanged: if (active) {
                    root.draggedRow = moduleRow
                    root.dragPosition = centroid.scenePosition
                    dragMarker.Drag.active = true
                  }
                  onCentroidChanged: if (active) root.dragPosition = centroid.scenePosition
                  onGrabChanged: transition => {
                    if (root.draggedRow !== moduleRow) return
                    if (transition === PointerDevice.UngrabExclusive) {
                      dragMarker.Drag.drop()
                      root.draggedRow = null
                    } else if (transition === PointerDevice.CancelGrabExclusive) {
                      dragMarker.Drag.cancel()
                      root.draggedRow = null
                    }
                  }
                }
              }

            }
          }

          ChoiceMenu {
            visible: moduleRow.moduleEnabled && (moduleRow.def.graph === true || moduleRow.def.ring === true)
            x: Commons.Style.space(12) + moduleSwitch.width + Commons.Style.space(12)
            width: parent.width - x
            label: "Look"
            options: Model.styleOptions(moduleRow.moduleId)
            value: Model.moduleStyle(root.settings, moduleRow.moduleId)
            onChanged: function(value) { root.set(moduleRow.moduleId + "Style", value) }
          }

          Column {
            visible: moduleRow.moduleEnabled && moduleRow.moduleId === "disks"
            x: Commons.Style.space(12) + moduleSwitch.width + Commons.Style.space(12)
            width: parent.width - x
            spacing: 0

            Repeater {
              model: moduleRow.moduleId === "disks" ? root.diskOptions.length : 0

              delegate: Column {
                id: diskRow
                required property int index
                readonly property var option: root.diskOptions[index] || ({})
                readonly property string disk: String(option.value || "")
                readonly property int position: root.diskIndex(disk)
                width: parent ? parent.width : 0
                spacing: 0

                FlagRow {
                  label: String(diskRow.option.label || "")
                  checked: diskRow.position !== -1
                  onToggled: root.setBarDisk(diskRow.disk, !checked, "")
                }

                ChoiceRow {
                  visible: diskRow.position !== -1
                  indent: Commons.Style.space(14)
                  label: "Show"
                  options: Model.DISK_SHOWS
                  value: diskRow.position === -1 ? "speed" : root.barDiskList[diskRow.position].show
                  onChanged: function(value) { root.setBarDisk(diskRow.disk, true, value) }
                }
              }
            }
          }

          Column {
            visible: moduleRow.moduleEnabled && moduleRow.moduleId === "gpu" && root.gpuOptions.length > 1
            x: Commons.Style.space(12) + moduleSwitch.width + Commons.Style.space(12)
            width: parent.width - x
            spacing: 0

            Repeater {
              model: moduleRow.moduleId === "gpu" ? root.gpuOptions.length : 0

              delegate: FlagRow {
                required property int index
                readonly property var card: root.gpuOptions[index] || ({})
                label: Model.gpuTitle(card)
                checked: root.selectedGpuIds.indexOf(Model.gpuId(card)) !== -1
                onToggled: root.setBarGpu(Model.gpuId(card), !checked)
              }
            }
          }

          FlagRow {
            visible: moduleRow.moduleEnabled && moduleRow.moduleId === "gpu" && root.gpuOptions.some(function(card) { return Model.gpuMemoryPercent(card) !== null })
            indent: Commons.Style.space(12) + moduleSwitch.width + Commons.Style.space(12)
            label: "Show VRAM in bar"
            checked: Model.flag(root.settings, "showGpuMemory")
            onToggled: root.set("showGpuMemory", !checked)
          }

          Column {
            visible: moduleRow.moduleEnabled && moduleRow.moduleId === "sensors"
            x: Commons.Style.space(12) + moduleSwitch.width + Commons.Style.space(12)
            width: parent.width - x
            spacing: 0

            Repeater {
              model: moduleRow.moduleId === "sensors" ? root.sensorOptions.length : 0

              delegate: FlagRow {
                required property int index
                readonly property var option: root.sensorOptions[index] || ({})
                label: String(option.label || "")
                checked: root.barSensorIds.indexOf(String(option.value)) !== -1
                onToggled: root.setBarSensor(String(option.value), !checked)
              }
            }
          }
        }
      }
    }
  }
  Card {
    foreground: root.foreground
    spacing: Commons.Style.space(6)

    SectionTitle { text: "Panel"; fontFamily: root.fontFamily }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Tabs shown in the panel and the sections on each page."
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.pages.length

      delegate: Column {
        id: pageRow
        required property int index
        readonly property string pageId: String(root.pages[index] || "")
        readonly property var def: Model.moduleDef(pageId)
        readonly property bool pageEnabled: root.tabModules.indexOf(pageId) !== -1
        readonly property var sections: Model.PANEL_SECTIONS[pageId] || []
        readonly property var choices: Model.PANEL_CHOICES[pageId] || []

        width: parent.width
        spacing: 0
        topPadding: Commons.Style.space(4)

        FlagRow {
          label: pageRow.def.label
          bold: true
          checked: pageRow.pageEnabled
          onToggled: root.setTabEnabled(pageRow.pageId, !pageRow.pageEnabled)
        }

        Repeater {
          model: pageRow.pageEnabled ? pageRow.sections.length : 0

          delegate: FlagRow {
            required property int index
            readonly property var section: pageRow.sections[index] || ({})
            indent: Commons.Style.space(26)
            label: String(section.label || "")
            checked: Model.flag(root.settings, String(section.key || ""))
            onToggled: root.set(String(section.key || ""), !checked)
          }
        }

        ChoiceMenu {
          visible: pageRow.pageEnabled && pageRow.pageId === "disks" && root.diskOptions.length > 1
          x: Commons.Style.space(26)
          width: parent.width - x
          label: "Drive the page follows"
          options: root.diskOptions
          value: Model.stableDiskId(root.snapshot, Model.settingValue(root.settings, "disksSource"))
          onChanged: function(value) { root.set("disksSource", value) }
        }

        Repeater {
          model: pageRow.pageEnabled ? pageRow.choices.length : 0

          delegate: ChoiceRow {
            required property int index
            readonly property var choice: pageRow.choices[index] || ({})
            indent: Commons.Style.space(26)
            label: String(choice.label || "")
            options: choice.options || []
            value: String(Model.settingValue(root.settings, String(choice.key || "")))
            onChanged: function(value) { root.set(String(choice.key || ""), value) }
          }
        }
      }
    }

    PanelSeparator { foreground: root.foreground }

    FlagRow {
      label: "Top processes on every page"
      checked: Model.flag(root.settings, "showProcesses")
      onToggled: root.set("showProcesses", !checked)
    }
  }
  Card {
    foreground: root.foreground
    spacing: Commons.Style.space(6)

    SectionTitle { text: "General"; fontFamily: root.fontFamily }

    ChoiceRow {
      label: "Bar labels"
      options: [{ value: "text", label: "Letters" }, { value: "inline", label: "Inline" }, { value: "icon", label: "Icons" }, { value: "none", label: "None" }]
      value: String(Model.settingValue(root.settings, "barLabels"))
      onChanged: function(value) { root.set("barLabels", value) }
    }

    ChoiceRow {
      label: "Temperature"
      options: [{ value: "Celsius", label: "°C" }, { value: "Fahrenheit", label: "°F" }]
      value: String(Model.settingValue(root.settings, "temperatureUnit"))
      onChanged: function(value) { root.set("temperatureUnit", value) }
    }

    FlagRow {
      label: "Color temperature readouts"
      checked: Model.flag(root.settings, "colorTemperatureIcons")
      onToggled: root.set("colorTemperatureIcons", !checked)
    }

    FlagRow {
      label: "Utilization colors"
      checked: Model.flag(root.settings, "utilizationColors")
      onToggled: root.set("utilizationColors", !checked)
    }

    Repeater {
      model: Model.flag(root.settings, "utilizationColors") ? [
        { key: "utilizationLowColor", label: "Low (<25%)" },
        { key: "utilizationNormalColor", label: "Normal (25–59%)" },
        { key: "utilizationWarningColor", label: "Warning (60–84%)" },
        { key: "utilizationCriticalColor", label: "Critical (85%+)" }
      ] : []

      delegate: ColorRow {
        required property var modelData
        key: String(modelData.key)
        label: String(modelData.label)
      }
    }

    StepperRow {
      label: "Refresh every"
      value: root.num("refreshSeconds")
      unit: "s"
      stops: Model.REFRESH_STOPS_SECONDS
      onChanged: function(value) { root.set("refreshSeconds", value) }
    }

    ChoiceRow {
      label: "History range"
      options: [{ value: "live", label: "Live" }, { value: "1h", label: "1 hour" }, { value: "24h", label: "24 hours" }]
      value: String(Model.settingValue(root.settings, "historySpan"))
      onChanged: function(value) { root.set("historySpan", value) }
    }

    StepperRow {
      label: "Live history"
      value: root.num("historySeconds")
      stops: Model.HISTORY_STOPS_SECONDS
      duration: true
      onChanged: function(value) { root.set("historySeconds", value) }
    }

    Text {
      width: parent.width
      text: "The 1-hour and 24-hour views keep peak readings across shell restarts and are saved once a minute."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }

    StepperRow {
      label: "Bar graph width"
      value: root.num("graphWidth")
      unit: "px"
      minimum: 16
      maximum: 120
      step: 4
      onChanged: function(value) { root.set("graphWidth", value) }
    }

    Item {
      width: parent.width
      height: resetButton.implicitHeight + Commons.Style.space(4)

      Button {
        id: resetButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Reset to defaults"
        bordered: true
        foreground: root.foreground
        onClicked: if (root.host && typeof root.host.resetSettings === "function") root.host.resetSettings()
      }
    }
  }

  component ChoiceMenu: Column {
    id: menu

    property string label: ""
    property var options: []
    property string value: ""
    signal changed(string value)

    function valueAt(index) {
      var option = options[index]
      return String(option && typeof option === "object" ? option.value : option)
    }

    function selectedIndex() {
      for (var i = 0; i < options.length; i++) if (valueAt(i) === value) return i
      return 0
    }

    spacing: Commons.Style.space(3)

    Text {
      text: menu.label
      color: root.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
    }

    ShellUi.PopupSelect {
      width: parent.width
      shell: root.host ? root.host.shell : null
      choices: menu.options.map(function(option) {
        return option && typeof option === "object"
          ? { label: String(option.label), value: String(option.value) }
          : { label: String(option), value: String(option) }
      })
      selectedIndex: menu.selectedIndex()
      onActivated: function(index) { menu.changed(menu.valueAt(index)) }
    }
  }

  component FlagRow: Item {
    id: flagRow

    property string label: ""
    property bool bold: false
    property bool checked: false
    property real indent: 0

    signal toggled()

    width: parent ? parent.width : implicitWidth
    height: Commons.Style.space(26)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: flagRow.indent
      anchors.right: flagSwitch.left
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: flagRow.label
      color: root.foreground
      opacity: flagRow.checked ? 0.9 : 0.6
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      font.bold: flagRow.bold
      elide: Text.ElideRight
    }

    ShellUi.ToggleSwitch {
      id: flagSwitch
      shell: root.host ? root.host.shell : null
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: flagRow.checked
      onToggled: flagRow.toggled()
    }

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: flagSwitch.width + Commons.Style.space(10)
      cursorShape: Qt.PointingHandCursor
      onClicked: flagRow.toggled()
    }
  }

  component ChoiceRow: Item {
    id: choiceRow

    property string label: ""
    property var options: []
    property string value: ""
    property real indent: 0

    signal changed(string value)

    width: parent ? parent.width : implicitWidth
    height: Math.max(Commons.Style.space(30), chips.implicitHeight + Commons.Style.space(4))

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: choiceRow.indent
      anchors.right: chips.left
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: choiceRow.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      elide: Text.ElideRight
    }

    Row {
      id: chips
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Commons.Style.space(4)

      Repeater {
        model: choiceRow.options
        delegate: Button {
          required property var modelData
          text: String(modelData.label || modelData.value || modelData)
          selected: String(modelData.value || modelData) === choiceRow.value
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Commons.Style.font.caption
          onClicked: choiceRow.changed(String(modelData.value || modelData))
        }
      }
    }
  }

  component StepperRow: Item {
    id: stepper

    property string label: ""
    property real value: 0
    property string unit: ""
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property var stops: []
    property bool duration: false

    readonly property bool stepped: Array.isArray(stops) && stops.length > 0
    readonly property int stopIndex: stepped ? Model.nearestStopIndex(value, stops) : -1
    readonly property bool canDecrease: stepped ? stopIndex > 0 : value > minimum
    readonly property bool canIncrease: stepped ? stopIndex < stops.length - 1 : value < maximum
    readonly property string valueText: duration ? Units.largestUnitText(value) || Math.round(value) + "s" : stepped ? Model.intervalText(value) : String(Math.round(value))

    signal changed(real value)

    function nudge(direction) {
      if (stepped) {
        var idx = Math.max(0, Math.min(stops.length - 1, stopIndex + direction))
        if (stops[idx] !== value) changed(stops[idx])
        return
      }
      var next = Math.max(minimum, Math.min(maximum, value + direction * step))
      if (next !== value) changed(next)
    }

    width: parent ? parent.width : implicitWidth
    height: Commons.Style.space(26)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: controls.left
      anchors.rightMargin: Commons.Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: stepper.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      elide: Text.ElideRight
    }

    Row {
      id: controls
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Commons.Style.space(4)

      PanelActionButton {
        iconText: "󰍴"
        enabled: stepper.canDecrease
        foreground: root.foreground
        fontFamily: root.fontFamily
        size: Commons.Style.space(22)
        onClicked: stepper.nudge(-1)
      }

      Item {
        width: Commons.Style.space(84)
        height: Commons.Style.space(22)

        Measure {
          anchors.centerIn: parent
          value: stepper.valueText
          unit: stepper.unit
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }

      PanelActionButton {
        iconText: "󰐕"
        enabled: stepper.canIncrease
        foreground: root.foreground
        fontFamily: root.fontFamily
        size: Commons.Style.space(22)
        onClicked: stepper.nudge(1)
      }
    }
  }

  component ColorRow: Item {
    id: colorRow

    property string key: ""
    property string label: ""
    property bool invalid: false
    property string editStartText: ""
    readonly property string settingColor: Model.utilizationSettingColor(root.settings, key, root.lightTheme)
    onSettingColorChanged: if (!input.activeFocus) input.text = settingColor

    width: parent ? parent.width : implicitWidth
    height: Commons.Style.space(30) + (invalid ? Commons.Style.space(14) : 0)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: input.left
      anchors.rightMargin: Commons.Style.space(8)
      anchors.verticalCenter: input.verticalCenter
      text: colorRow.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.bodySmall
      elide: Text.ElideRight
    }

    Rectangle {
      id: swatch
      anchors.right: parent.right
      anchors.verticalCenter: input.verticalCenter
      width: Commons.Style.space(18)
      height: width
      radius: Commons.Style.space(3)
      color: colorRow.settingColor
      border.color: Commons.Util.scaleAlpha(root.foreground, 0.25)
      border.width: Commons.Style.normalBorderWidth
    }

    KeyField {
      id: input
      anchors.right: swatch.left
      anchors.rightMargin: Commons.Style.space(6)
      anchors.top: parent.top
      anchors.topMargin: Commons.Style.space(2)
      width: Commons.Style.space(88)
      height: Commons.Style.space(26)
      text: colorRow.settingColor
      placeholderText: "#RRGGBB"
      maximumLength: 7
      horizontalAlignment: Text.AlignRight
      foreground: root.foreground
      verticalPadding: Commons.Style.space(4)
      font.pixelSize: Commons.Style.font.caption
      onTextChanged: colorRow.invalid = false
      onActiveFocusChanged: {
        if (activeFocus) colorRow.editStartText = text
        root.focusedColorEditors = Math.max(0, root.focusedColorEditors + (activeFocus ? 1 : -1))
        if (root.host) root.host.searchActive = root.focusedColorEditors > 0
      }
      onEditingFinished: {
        if (text === colorRow.editStartText) return
        if (text === "" || Model.validHexColor(text)) {
          root.set(colorRow.key, text.toLowerCase())
          colorRow.editStartText = text
        } else colorRow.invalid = true
      }
      Keys.onEscapePressed: function(event) {
        focus = false
        event.accepted = true
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: colorRow.invalid
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: "Use a six-digit hex color, or clear for the theme default."
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }
  }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs
import qs.Commons as Commons
import "Model.js" as Model
import "ui" as UI

Item {
  id: root

  required property var shell
  property Item popupAnchor: root
  property bool popupEnabled: true
  property var settings: ({})
  property string currentTab: "cpu"
  readonly property int historyRange: Model.historyRange(Model.settingValue(settings, "historySpan"))
  readonly property int scrollStep: Commons.Style.space(48)
  property bool processesExpanded: false
  property string processQuery: ""
  property bool searchActive: false
  property var searchField: null
  property bool fullHeld: false

  readonly property var service: shell.systemStats
  readonly property var box: shell.style.box("systemstats")
  readonly property real topInset: box.margin[0] + box.padding[0]
  readonly property real rightInset: box.margin[1] + box.padding[1]
  readonly property real bottomInset: box.margin[2] + box.padding[2]
  readonly property real leftInset: box.margin[3] + box.padding[3]
  readonly property var monitorCommands: ({ gpu: "nvtop", disks: "dua i " + shell.home })
  readonly property int barSize: Commons.Style.bar.sizeHorizontal
  readonly property int graphWidth: Math.round(Model.clamp(Model.settingValue(settings, "graphWidth"), 16, 120))
  readonly property string temperatureUnit: String(Model.settingValue(settings, "temperatureUnit")).toLowerCase() === "fahrenheit" ? "Fahrenheit" : "Celsius"
  readonly property bool colorTemperatureIcons: Model.flag(settings, "colorTemperatureIcons")
  readonly property bool publicIpEnabled: Model.flag(settings, "publicIp")
  readonly property bool hasGpu: !!(service && service.hasGpu)
  readonly property bool hasBattery: !!(service && service.hasBattery)
  readonly property var configuredModules: Model.parseModules(Model.settingValue(settings, "modules"))
  readonly property var snapshot: service ? service.snapshot : ({})
  readonly property var barModules: {
    var out = []
    var cards = Model.selectedGpus(snapshot, Model.settingValue(settings, "barGpus"))
    var perDisk = (snapshot.disks || {}).perDisk || {}
    var drives = Model.barDisksHere(snapshot, settings).map(function(entry) {
      return { disk: Model.resolveDisk(snapshot, entry.disk), show: entry.show }
    }).filter(function(entry) { return entry.disk !== "" || Object.keys(perDisk).length === 0 })
    for (var module of configuredModules) {
      if (module === "power" || (module === "battery" && !hasBattery)) continue
      if (module === "gpu") {
        for (var card of cards) {
          out.push({ id: "gpu", gpuId: Model.gpuId(card), label: cards.length > 1 ? Model.gpuShort(card) : "" })
          if (Model.flag(settings, "showGpuMemory") && Model.gpuMemoryPercent(card) !== null)
            out.push({ id: "gpuMemory", gpuId: Model.gpuId(card), label: "VRM" })
        }
      } else if (module === "disks") {
        for (var drive of drives)
          out.push({ id: "disks", disk: drive.disk || "all", diskShow: drive.show, label: drives.length > 1 ? Model.diskShort(drive.disk) : "" })
      } else out.push({ id: module })
    }
    return out.length ? out : [{ id: "cpu" }]
  }
  readonly property var stableSettings: Model.stableSettings(settings, snapshot)
  onStableSettingsChanged: if (stableSettings) Qt.callLater(adoptStableSettings)

  function adoptStableSettings() {
    var changes = Model.stableSettings(settings, snapshot)
    if (changes) saveSettings(Object.assign({}, settings, changes))
  }
  readonly property var moduleTabs: Model.panelTabs(hasGpu, hasBattery, Model.settingValue(settings, "tabs"))
  readonly property var panelTabs: moduleTabs.concat(["alerts", "settings"])
  readonly property bool processesSearchable: currentTab === "cpu" || currentTab === "disks" || currentTab === "network"
  readonly property string barSensors: String(Model.settingValue(settings, "barSensors"))
  readonly property string barLabels: {
    const value = String(Model.settingValue(settings, "barLabels")).toLowerCase()
    return value === "icon" || value === "inline" || value === "none" ? value : "text"
  }
  readonly property bool opened: panel.open
  implicitWidth: inlineReadouts.width + leftInset + rightInset + Commons.Style.space(2)
  implicitHeight: barSize + topInset + bottomInset

  function mergeSettings(value) {
    var merged = {}
    for (var key in Model.SETTINGS) merged[key] = Model.SETTINGS[key]
    if (value && typeof value === "object") for (var own in value) merged[own] = value[own]
    return merged
  }

  function loadSettings(raw) {
    try {
      settings = mergeSettings(JSON.parse(String(raw)))
    } catch (error) { console.warn("systemstats settings: " + error); settings = ({}) }
  }

  function saveSettings(current) {
    settings = current
    settingsFile.setText(JSON.stringify(current, null, 2) + "\n")
  }

  function persist(key, value) {
    var current = Object.assign({}, settings)
    current[key] = value
    saveSettings(current)
  }

  function resetSettings() { saveSettings(mergeSettings(null)) }

  function styleFor(module) { return Model.moduleStyle(settings, module) }

  function showTab(id) {
    var tab = Model.tabFor(id)
    if (panelTabs.indexOf(tab) === -1) tab = panelTabs[0]
    if (currentTab !== tab) {
      currentTab = tab
      scrollArea.contentY = 0
    }
  }

  function toggleModule(id) {
    var tab = Model.tabFor(id)
    if (opened && currentTab === tab) { close(); return }
    showTab(tab)
    if (shell.popupName !== "systemstats") shell.togglePopup("systemstats")
  }

  function close() {
    if (shell.popupName === "systemstats") shell.closePopup()
  }

  function cycleTab(delta) {
    var index = panelTabs.indexOf(currentTab)
    index = (Math.max(0, index) + delta + panelTabs.length) % panelTabs.length
    showTab(panelTabs[index])
  }

  function scrollBy(pixels) {
    var limit = Math.max(0, scrollArea.contentHeight - scrollArea.height)
    scrollArea.contentY = Math.max(0, Math.min(limit, scrollArea.contentY + pixels))
  }

  function setProcessesExpanded(value) {
    processesExpanded = value === true
    if (!processesExpanded) { processQuery = ""; searchActive = false }
    syncFull()
  }

  function syncFull() {
    var wanted = opened && processesExpanded && processesSearchable
    if (!service || wanted === fullHeld) return
    fullHeld = wanted
    if (wanted) service.acquireFull()
    else service.releaseFull()
  }

  function focusSearch() {
    if (!processesSearchable) return
    if (!processesExpanded) setProcessesExpanded(true)
    Qt.callLater(function() { if (root.searchField) root.searchField.forceActiveFocus() })
  }

  function handleKey(event) {
    if (searchActive) return false
    var text = String(event.text || "").toLowerCase()
    if (event.key === Qt.Key_Escape) { close(); return true }
    if (event.key === Qt.Key_Left || text === "h") { cycleTab(-1); return true }
    if (event.key === Qt.Key_Right || text === "l") { cycleTab(1); return true }
    if (event.key === Qt.Key_Up || text === "k") { scrollBy(-scrollStep); return true }
    if (event.key === Qt.Key_Down || text === "j") { scrollBy(scrollStep); return true }
    if (text === "r") { if (publicIpEnabled) service.requestPublicIp(true); return true }
    if (text === "s" || text === ",") { showTab("settings"); return true }
    if (text === "a") { showTab("alerts"); return true }
    if (text === "/" && processesSearchable) { focusSearch(); return true }
    var digit = parseInt(text, 10)
    if (digit >= 1 && digit <= moduleTabs.length) { showTab(moduleTabs[digit - 1]); return true }
    return false
  }

  function pushSettings() {
    if (service) service.configure(
      Model.settingValue(settings, "refreshSeconds"),
      Model.settingValue(settings, "historySeconds"))
  }

  onOpenedChanged: {
    if (!service) return
    if (opened) { service.acquireDetail(); service.setFocus(currentTab) }
    else { service.releaseDetail(); service.setFocus(""); searchActive = false }
    syncFull()
  }
  onCurrentTabChanged: {
    if (opened && service) service.setFocus(currentTab)
    syncFull()
  }
  onPanelTabsChanged: if (panelTabs.indexOf(currentTab) === -1) currentTab = panelTabs[0]
  onSettingsChanged: pushSettings()

  FileView {
    id: settingsFile
    path: root.shell.home + "/.config/quickshell/systemstats/settings.json"
    watchChanges: true
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
  }

  Component {
    id: readoutsComponent
    Grid {
      columns: Math.max(1, root.barModules.length)
      rows: 1
      horizontalItemAlignment: Grid.AlignHCenter

      Repeater {
        model: root.barModules
        delegate: UI.BarReadout {
          required property var modelData
          shell: root.shell
          box: root.shell.style.box("systemstats." + modelData.id)
          barSize: root.barSize
          module: modelData.id
          gpuId: modelData.gpuId || ""
          shortLabel: modelData.label || ""
          service: root.service
          settings: root.settings
          mode: root.styleFor(module === "gpuMemory" ? "gpu" : module)
          graphWidth: root.graphWidth
          temperatureUnit: root.temperatureUnit
          colorTemperatureIcons: root.colorTemperatureIcons
          disksSource: modelData.disk || "all"
          diskShow: modelData.diskShow || "speed"
          barSensors: root.barSensors
          labelMode: root.barLabels
          onActivated: function(id, button) {
            if (button === Qt.LeftButton) root.toggleModule(id)
            else if (button === Qt.RightButton && id !== "network" && id !== "cpu") {
              root.close()
              root.shell.run(["hyprshell", "util/sysmon-launch"].concat(Model.tabFor(id) in root.monitorCommands ? ["-e", root.monitorCommands[Model.tabFor(id)]] : []))
            }
            else if (button === Qt.MiddleButton && root.publicIpEnabled) root.service.requestPublicIp(true)
          }
        }
      }
    }
  }

  Loader {
    id: inlineReadouts
    sourceComponent: readoutsComponent
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: (root.leftInset - root.rightInset) / 2
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: (root.topInset - root.bottomInset) / 2
  }

  PopupCard {
    id: panel
    anchorItem: root.popupAnchor
    shell: root.shell
    popupName: "systemstats"
    keyboardHint: "←→ Tabs  ↑↓ Scroll  1–" + root.moduleTabs.length + " Tab" + (root.processesSearchable ? "  / Search" : "") + "  Esc"
    popupEnabled: root.popupEnabled
    wantsKeyboard: true
    contentWidth: Math.max(Commons.Style.space(420), Math.ceil(tabs.spelledWidth) + padding * 2)
    contentHeight: Commons.Style.space(680)

    function handleKey(event) { return root.handleKey(event) || defaultKey(event) }

    UI.ModuleTabs {
      id: tabs
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      tabs: root.moduleTabs.concat(["alerts"])
      settingsTab: "settings"
      current: root.currentTab
      foreground: root.shell.foreground
      fontFamily: root.shell.fontFamily
      onActivated: function(id) { root.showTab(id) }
    }

    Text {
      id: statusLine
      anchors.top: tabs.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      readonly property string message: !root.service.ready ? "Starting the sampler…" : root.service.samplerError ? "Sampler: " + root.service.samplerError : ""
      visible: message !== ""
      height: visible ? implicitHeight + Commons.Style.space(10) : 0
      verticalAlignment: Text.AlignBottom
      text: message
      color: root.shell.foreground
      opacity: Commons.Style.mutedTextAlpha
      font.family: root.shell.fontFamily
      font.pixelSize: Commons.Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Flickable {
      id: scrollArea
      anchors.top: statusLine.bottom
      anchors.topMargin: Commons.Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      contentWidth: width
      contentHeight: pageLoader.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: PopupScrollBar { shell: root.shell }

      WheelHandler {
        id: wheelScroll
        readonly property int anglePerNotch: 120
        readonly property var styleHints: Qt.styleHints
        target: null
        enabled: scrollArea.interactive
        acceptedDevices: PointerDevice.Mouse
        onWheel: event => root.scrollBy(-event.pixelDelta.y
          || -event.angleDelta.y / wheelScroll.anglePerNotch * wheelScroll.styleHints.wheelScrollLines * root.scrollStep)
      }

      Loader {
        id: pageLoader
        width: scrollArea.width
        active: panel.open || panel.visible
        source: Qt.resolvedUrl("ui/" + Model.pageFile(root.currentTab))
      }

      Binding { target: pageLoader.item; property: "service"; value: root.service; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "historyRange"; value: root.historyRange; when: pageLoader.status === Loader.Ready && pageLoader.item && pageLoader.item.hasOwnProperty("historyRange") }
      Binding { target: pageLoader.item; property: "settings"; value: root.settings; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "host"; value: root; when: pageLoader.status === Loader.Ready && pageLoader.item && pageLoader.item.hasOwnProperty("host") }
      Binding { target: pageLoader.item; property: "temperatureUnit"; value: root.temperatureUnit; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "publicIpEnabled"; value: root.publicIpEnabled; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "foreground"; value: root.shell.foreground; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "fontFamily"; value: root.shell.fontFamily; when: pageLoader.status === Loader.Ready }
    }
  }

  Component.onCompleted: {
    pushSettings()
    service.registerInstance(root)
  }

  Component.onDestruction: {
    if (opened) service.releaseDetail()
    if (fullHeld) service.releaseFull()
    service.unregisterInstance(root)
  }
}

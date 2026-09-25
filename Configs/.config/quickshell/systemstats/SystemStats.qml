pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.Commons
import "Model.js" as Model
import "ui" as UI

Item {
  id: root

  required property var shell
  property bool popupsAllowed: true
  property var settingsStore: ({})
  readonly property string settingsOrientation: shell.barLayout.panel === "vertical" ? "vertical" : "horizontal"
  readonly property var settings: settingsStore[settingsOrientation] || Model.SETTINGS
  property string currentTab: "cpu"
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
  readonly property bool vertical: shell.mode === "vertical"
  readonly property int barSize: Style.bar.sizeHorizontal
  readonly property int graphWidth: Math.round(Model.clamp(Model.settingValue(settings, "graphWidth"), 16, 120))
  readonly property string temperatureUnit: String(Model.settingValue(settings, "temperatureUnit")).toLowerCase() === "fahrenheit" ? "Fahrenheit" : "Celsius"
  readonly property bool colorTemperatureIcons: Model.flag(settings, "colorTemperatureIcons")
  readonly property bool publicIpEnabled: Model.flag(settings, "publicIp")
  readonly property bool hasGpu: !!(service && service.hasGpu)
  readonly property bool hasBattery: !!(service && service.hasBattery)
  readonly property var configuredModules: Model.parseModules(Model.settingValue(settings, "modules"))
  readonly property var barModules: configuredModules.filter(function(module) {
    return (module !== "gpu" || hasGpu) && (module !== "battery" || hasBattery)
  })
  readonly property var moduleTabs: Model.panelTabs(hasGpu, hasBattery, Model.settingValue(settings, "tabs"))
  readonly property var panelTabs: moduleTabs.concat(["alerts", "settings"])
  readonly property string disksSource: String(Model.settingValue(settings, "disksSource") || "all")
  readonly property string barSensors: String(Model.settingValue(settings, "barSensors") || "cpu")
  readonly property string barLabels: String(Model.settingValue(settings, "barLabels")).toLowerCase() === "icon" ? "icon" : "text"
  readonly property bool opened: panel.open
  implicitWidth: vertical ? barSize : inlineReadouts.width + leftInset + rightInset + Style.space(2)
  implicitHeight: (vertical && overflowReadouts.height > 0 ? overflowReadouts.height : barSize) + topInset + bottomInset

  function mergeSettings(value) {
    var merged = {}
    for (var key in Model.SETTINGS) merged[key] = Model.SETTINGS[key]
    if (value && typeof value === "object") for (var own in value) merged[own] = value[own]
    return merged
  }

  function loadSettings(raw) {
    try {
      var data = JSON.parse(String(raw))
      var legacy = data.vertical || data.horizontal ? null : data
      settingsStore = { vertical: mergeSettings(data.vertical || legacy), horizontal: mergeSettings(data.horizontal || legacy) }
    } catch (error) { console.warn("systemstats settings: " + error); settingsStore = ({}) }
  }

  function saveSettings(current) {
    var next = { vertical: settingsStore.vertical || mergeSettings(null), horizontal: settingsStore.horizontal || mergeSettings(null) }
    next[settingsOrientation] = current
    settingsStore = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
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
    shell.togglePopup("systemstats")
  }

  function close() {
    if (shell.popupName === "systemstats") shell.closePopup()
  }

  function cycleTab(delta) {
    var index = panelTabs.indexOf(currentTab)
    index = (Math.max(0, index) + delta + panelTabs.length) % panelTabs.length
    showTab(panelTabs[index])
  }

  function scrollBy(steps) {
    var limit = Math.max(0, scrollArea.contentHeight - scrollArea.height)
    scrollArea.contentY = Math.max(0, Math.min(limit, scrollArea.contentY + steps * Style.space(48)))
  }

  function setProcessesExpanded(value) {
    processesExpanded = value === true
    if (!processesExpanded) { processQuery = ""; searchActive = false }
    syncFull()
  }

  function syncFull() {
    var wanted = opened && processesExpanded
    if (!service || wanted === fullHeld) return
    fullHeld = wanted
    if (wanted) service.acquireFull()
    else service.releaseFull()
  }

  function focusSearch() {
    if (!processesExpanded) setProcessesExpanded(true)
    Qt.callLater(function() { if (root.searchField) root.searchField.forceActiveFocus() })
  }

  function handleKey(event) {
    if (searchActive) return false
    var text = String(event.text || "").toLowerCase()
    if (event.key === Qt.Key_Escape) { close(); return true }
    if (event.key === Qt.Key_Left || text === "h") { cycleTab(-1); return true }
    if (event.key === Qt.Key_Right || text === "l") { cycleTab(1); return true }
    if (event.key === Qt.Key_Up || text === "k") { scrollBy(-1); return true }
    if (event.key === Qt.Key_Down || text === "j") { scrollBy(1); return true }
    if (text === "r") { if (publicIpEnabled) service.requestPublicIp(true); return true }
    if (text === "s" || text === ",") { showTab("settings"); return true }
    if (text === "a") { showTab("alerts"); return true }
    if (text === "/") { focusSearch(); return true }
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
  onCurrentTabChanged: if (opened && service) service.setFocus(currentTab)
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
      columns: root.vertical ? 1 : Math.max(1, root.barModules.length)
      rows: root.vertical ? Math.max(1, root.barModules.length) : 1
      horizontalItemAlignment: root.vertical ? Grid.AlignLeft : Grid.AlignHCenter

      Repeater {
        model: root.barModules.length ? root.barModules : ["cpu"]
        delegate: UI.BarReadout {
          required property var modelData
          shell: root.shell
          box: root.shell.style.box("systemstats." + modelData)
          vertical: root.vertical
          barSize: root.barSize
          module: String(modelData)
          service: root.service
          mode: root.styleFor(module)
          graphWidth: root.graphWidth
          temperatureUnit: root.temperatureUnit
          colorTemperatureIcons: root.colorTemperatureIcons
          disksSource: root.disksSource
          barSensors: root.barSensors
          labelMode: root.barLabels
          onActivated: function(id, button) {
            if (button === Qt.LeftButton) root.toggleModule(id)
            else if (button === Qt.RightButton && id !== "network") root.shell.run(["hyprshell", "util/sysmon-launch"].concat(id in root.monitorCommands ? ["-e", root.monitorCommands[id]] : []))
            else if (button === Qt.MiddleButton && root.publicIpEnabled) root.service.requestPublicIp(true)
          }
        }
      }
    }
  }

  Loader {
    id: inlineReadouts
    active: !root.vertical
    sourceComponent: readoutsComponent
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: (root.leftInset - root.rightInset) / 2
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: (root.topInset - root.bottomInset) / 2
  }

  // The bar's layer surface clips at its edge, so vertical data needs its own surface.
  PopupWindow {
    id: overhang
    readonly property var anchorWindow: root.QsWindow.window
    visible: root.vertical && !root.shell.userHidden
    color: "transparent"
    implicitWidth: Math.max(root.width, overflowReadouts.width + root.leftInset + root.rightInset + Style.space(2))
    implicitHeight: root.height
    anchor {
      window: overhang.anchorWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1; rect.height: 1
      onAnchoring: {
        if (!overhang.anchorWindow) return
        const point = overhang.anchorWindow.contentItem.mapFromItem(root, 0, 0)
        anchor.rect.x = Math.round(point.x)
        anchor.rect.y = Math.round(point.y)
      }
    }
    Loader {
      id: overflowReadouts
      active: root.vertical
      sourceComponent: readoutsComponent
      anchors.left: parent.left
      anchors.leftMargin: root.leftInset
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: (root.topInset - root.bottomInset) / 2
    }
  }

  PopupCard {
    id: panel
    anchorItem: root
    shell: root.shell
    popupName: "systemstats"
    popupEnabled: root.popupsAllowed
    extraGrabWindows: root.vertical ? [overhang] : []
    wantsKeyboard: true
    contentWidth: Math.max(Style.space(500), Math.ceil(tabs.spelledWidth) + padding * 2)
    contentHeight: Style.space(680)

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
      height: visible ? implicitHeight + Style.space(10) : 0
      verticalAlignment: Text.AlignBottom
      text: message
      color: root.shell.foreground
      opacity: 0.6
      font.family: root.shell.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Flickable {
      id: scrollArea
      anchors.top: statusLine.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      contentWidth: width
      contentHeight: pageLoader.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: scrollArea.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

      Loader {
        id: pageLoader
        width: scrollArea.width
        active: panel.open || panel.visible
        source: Qt.resolvedUrl("ui/" + Model.pageFile(root.currentTab))
      }

      Binding { target: pageLoader.item; property: "service"; value: root.service; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "settings"; value: root.settings; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "host"; value: root; when: pageLoader.status === Loader.Ready && pageLoader.item && pageLoader.item.hasOwnProperty("host") }
      Binding { target: pageLoader.item; property: "temperatureUnit"; value: root.temperatureUnit; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "publicIpEnabled"; value: root.publicIpEnabled; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "foreground"; value: root.shell.foreground; when: pageLoader.status === Loader.Ready }
      Binding { target: pageLoader.item; property: "fontFamily"; value: root.shell.fontFamily; when: pageLoader.status === Loader.Ready }
    }
  }

  Component.onCompleted: {
    Color.shell = root.shell
    Style.shell = root.shell
    pushSettings()
    service.registerInstance(root)
  }

  Component.onDestruction: {
    if (opened) service.releaseDetail()
    if (fullHeld) service.releaseFull()
    service.unregisterInstance(root)
  }
}

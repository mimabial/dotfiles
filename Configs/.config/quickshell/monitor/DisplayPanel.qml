pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import "Ui"
import "Model.js" as Model

Panel {
  id: root
  moduleName: "display-panel"
  ipcTarget: "display-panel"
  manageIpc: false

  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string backendVersion: ""
  property bool serviceEnabled: false
  property bool serviceActive: false
  property bool serviceStateKnown: false
  property bool serviceActionPending: false
  property bool serviceTargetManaged: false
  property string serviceAction: ""
  property bool connectionGrace: false
  readonly property bool backendConnected: backendRuntime.socket.connected
  property var document: Model.emptyDocument()
  property bool documentReady: false
  property string lastError: ""
  property int requestSequence: 0
  property var pendingMethods: ({})
  property var pendingContexts: ({})
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool keyboardHelpOpen: false
  property string keyboardLayoutPane: "canvas"
  property int keyboardInspectorField: 0
  property int workspaceKeyboardIndex: 0
  property bool manualWorkspaceRulesInitialized: false
  property bool execEditing: false
  property string execDraft: ""

  property var editorDocument: Model.emptyEditorDocument()
  property var draftProfile: Model.emptyProfile()
  property var workspacePlan: []
  property bool editorReady: false
  property bool editorLoading: false
  property bool editPending: false
  property bool draftDirty: false
  property string sourceProfile: ""
  property string suggestedProfile: ""
  property string selectedOutputKey: ""
  property string activePage: "layout"
  property bool expanded: false
  property string inspectorPage: "display"
  property string selectedSavedProfileName: ""
  property string profileChoice: ""
  property bool profileModePending: false
  property bool creatingProfile: false
  property string saveName: ""
  property string previewTransaction: ""
  property string previewKind: ""
  property string previewDeadline: ""
  property int previewSeconds: 0
  property bool previewPending: false
  property int brightnessPercent: 1
  property int pendingBrightnessPercent: 1
  property bool brightnessAvailable: false
  property bool brightnessLoading: false
  property bool brightnessReadQueued: false
  property string brightnessReadConnector: ""
  property bool brightnessSetQueued: false
  property string brightnessSetConnector: ""
  property string pendingBrightnessConnector: ""
  readonly property var textSizes: [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  readonly property int textSizeIndex: Math.max(0, root.textSizes.indexOf(Style.textSize))

  readonly property var monitorSummaries: document && document.monitors instanceof Array ? document.monitors : []
  readonly property var layoutDisplays: root.daemonPreview && root.daemonPreview.profile
    ? Model.profileLayoutDisplays(root.daemonPreview.profile, root.editorDocument.displays)
    : (root.editorReady
      ? Model.profileLayoutDisplays(root.draftProfile, root.editorDocument.displays)
      : Model.layoutDisplays(root.backendConnected ? monitorSummaries : [], Quickshell.screens || []))
  readonly property var layoutBounds: Model.layoutBounds(layoutDisplays)
  readonly property string hiddenDisplays: root.daemonPreview && root.daemonPreview.profile
    ? Model.hiddenProfileDisplays(root.daemonPreview.profile)
    : (root.editorReady
      ? Model.hiddenProfileDisplays(root.draftProfile)
      : Model.hiddenDisplays(root.backendConnected ? monitorSummaries : []))
  readonly property int monitorCount: {
    return layoutDisplays.length
  }
  readonly property string activeProfile: root.managedChecked && document && document.active_profile
    ? String(document.active_profile.name || "")
    : ""
  readonly property string recommendedProfile: root.managedChecked && document && document.recommended_profile
    ? String(document.recommended_profile.name || "")
    : ""
  readonly property var daemonPreview: root.document && root.document.daemon && root.document.daemon.preview
    ? root.document.daemon.preview : null
  readonly property string pendingProfileName: root.daemonPreview
    ? String(root.daemonPreview.profile_name || "") : ""
  readonly property string profileOverride: root.document && root.document.daemon
    ? String(root.document.daemon.profile_override || "")
    : ""
  readonly property var exactDisplayProfile: Model.exactDisplayProfile(root.document)
  readonly property string exactDisplayProfileName: root.exactDisplayProfile
    ? String(root.exactDisplayProfile.name || "") : ""
  readonly property int connectedDisplayCount: root.document && root.document.monitors instanceof Array
    ? root.document.monitors.length : 0
  readonly property string displayedProfile: pendingProfileName !== ""
    ? pendingProfileName
    : (profileOverride !== "" ? profileOverride
      : (activeProfile !== "" ? activeProfile : recommendedProfile))
  readonly property bool profileAutomatic: root.profileOverride === ""
  readonly property string profileStatusTitle: {
    if (!root.managedChecked) return "Automatic profiles off"
    if (!root.documentReady) return root.serviceActionPending ? "Starting display service…" : "Loading profile…"
    if (root.pendingProfileName !== "") return root.pendingProfileName
    if (!root.profileAutomatic && root.displayedProfile !== "") return root.displayedProfile
    if (root.profileAutomatic && root.exactDisplayProfileName !== "") return root.exactDisplayProfileName
    if (root.profileAutomatic && root.connectedDisplayCount > 0) return "New display setup"
    return "Custom layout"
  }
  readonly property string profileStatusSubtitle: {
    if (!root.managedChecked) return "Turn on management for automatic profiles"
    if (!root.documentReady) return "Reading the active display layout"
    var displays = root.connectedDisplayCount === 1 ? "1 display" : root.connectedDisplayCount + " displays"
    if (root.pendingProfileName !== "") return displays + " · Awaiting confirmation"
    if (!root.profileAutomatic) return "Automatic matching is paused"
    if (root.exactDisplayProfileName !== "") return displays + " · Best match for this setup"
    if (root.connectedDisplayCount > 0) return "No saved profile matches these displays"
    return "No connected displays"
  }
  readonly property bool daemonUnmanaged: !!(root.document && root.document.daemon && root.document.daemon.unmanaged)
  readonly property bool managedChecked: serviceActionPending
    ? serviceTargetManaged
    : (root.documentReady && root.backendConnected
      ? !root.daemonUnmanaged
      : (serviceEnabled || serviceActive || backendConnected))
  readonly property string runningVersion: Model.releaseVersion(root.document ? root.document.version : "")
  readonly property string backendRelease: Model.releaseVersion(root.backendVersion)
  readonly property bool daemonOutdated: root.backendConnected
    && root.documentReady
    && Model.daemonNeedsRestart(root.backendVersion, root.document ? root.document.version : "")
  // Every actionable row in one list, so their cursor positions cannot drift
  // apart from what is on screen.
  readonly property var actionRows: {
    var rows = []
    if (root.serviceBroken)
      rows.push({
        id: "restart-service",
        icon: "󰑓",
        title: "Restart display service",
        subtitle: "Try the background service again"
      })
    else if (root.daemonOutdated)
      rows.push({
        id: "restart-service",
        icon: "󰑓",
        title: "Restart daemon",
        subtitle: "Running " + root.runningVersion + ", on disk " + root.backendRelease
      })
    return rows
  }
  readonly property int layoutRowIndex: 1 + root.actionRows.length
  readonly property bool serviceBroken: serviceStateKnown
    && serviceEnabled
    && !backendConnected
    && !connectionGrace
    && !serviceActionPending
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string socketPath: root.runtimeDir + "/hyprmoncfgd.sock"
  readonly property var previewCoordinator: {
    return root.shell ? root.shell.monitorPreviewCoordinator : null
  }
  readonly property bool barIconDimmed: root.serviceStateKnown
    && !root.managedChecked
    && !root.serviceActionPending
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property real unmanagedOpacity: 0.45
  // NumberField is backed by a QML int. Keep only that technical boundary;
  // workspace planning itself has no product-level maximum.
  readonly property int workspaceValueMaximum: 2147483647
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var selectedOutput: Model.outputByKey(root.draftProfile, root.selectedOutputKey)
  readonly property var selectedOutputMetadata: Model.editorMetadata(root.editorDocument.displays, root.selectedOutputKey)
  readonly property var brightnessTarget: Model.brightnessTarget(root.draftProfile,
    root.selectedOutputKey, root.editorDocument.displays)
  readonly property string brightnessConnector: String(root.brightnessTarget.connector || "")
  readonly property string brightnessDisplayLabel: String(root.brightnessTarget.label || "")
  readonly property var savedProfiles: root.editorDocument && root.editorDocument.profiles instanceof Array
    ? root.editorDocument.profiles : []
  readonly property var selectedSavedProfile: Model.savedProfileByName(root.editorDocument, root.selectedSavedProfileName)
  readonly property var selectedSavedSummary: Model.profileSummaryByName(root.document, root.selectedSavedProfileName)
  readonly property var selectedSavedWorkspacePlan: Model.profileWorkspacePlan(root.editorDocument, root.selectedSavedProfileName)
  readonly property var selectedSavedWorkspaceRows: Model.workspacePlanRows(root.selectedSavedWorkspacePlan, root.selectedSavedProfile)
  readonly property var selectedSavedMatchReasons: Model.profileMatchReasonRows(root.selectedSavedSummary)
  readonly property var selectedSavedHiddenRows: Model.profileHiddenDisplayRows(root.selectedSavedProfile)
  readonly property int selectedSavedDetailRowCount: 5
    + root.selectedSavedMatchReasons.length
    + root.selectedSavedHiddenRows.length
    + Math.max(1, root.selectedSavedWorkspaceRows.length)
  readonly property var workspaceRows: Model.workspacePlanRows(root.workspacePlan, root.draftProfile)
  readonly property var manualWorkspaceRows: Model.manualWorkspaceRows(root.draftProfile)
  readonly property int manualWorkspaceTargetCount: Model.manualWorkspaceTargetKeys(root.draftProfile).length
  readonly property string workspaceStrategy: String(((root.draftProfile || {}).workspaces || {}).strategy || "manual")
  readonly property bool workspaceGroupSizeApplicable: root.workspaceStrategy === "sequential"
  readonly property int workspaceListKeyboardStart: root.workspaceGroupSizeApplicable ? 4 : 3
  readonly property string selectedWorkspaceDisplayKey: {
    var index = root.workspaceKeyboardIndex - root.workspaceListKeyboardStart
    if (index < 0) return ""
    var settings = (root.draftProfile || {}).workspaces || {}
    if (String(settings.strategy || "") === "manual") {
      if (index >= root.manualWorkspaceRows.length) return ""
      return String((root.manualWorkspaceRows[index] || {}).output_key || "")
    }
    var order = settings.monitor_order instanceof Array ? settings.monitor_order : []
    return index < order.length ? String(order[index] || "") : ""
  }
  readonly property var pageOptions: [
    { value: "layout", label: "1  Layout" },
    { value: "profiles", label: "2  Profiles" },
    { value: "workspaces", label: "3  Workspaces" }
  ]
  readonly property var inspectorOptions: [
    { value: "display", label: "Display" },
    { value: "color", label: "Color" }
  ]
  readonly property var displayKeyboardFields: [0, 1, 2, 5, 6, 7, 8, 9]
  readonly property var colorKeyboardFields: [3, 4, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  readonly property var vrrOptions: [
    { value: "0", label: "Off" },
    { value: "1", label: "On" },
    { value: "2", label: "Fullscreen" }
  ]
  readonly property var bitdepthOptions: [
    { value: "8", label: "8-bit" },
    { value: "10", label: "10-bit" }
  ]
  readonly property var colorManagementOptions: [
    { value: "srgb", label: "sRGB" },
    { value: "auto", label: "Auto" },
    { value: "wide", label: "Wide gamut" },
    { value: "hdr", label: "HDR" },
    { value: "hdredid", label: "HDR EDID" },
    { value: "dcip3", label: "DCI-P3" },
    { value: "dp3", label: "Display P3" },
    { value: "adobe", label: "Adobe RGB" },
    { value: "edid", label: "EDID" }
  ]
  readonly property var triStateOptions: [
    { value: "-1", label: "Force off" },
    { value: "0", label: "Auto" },
    { value: "1", label: "Force on" }
  ]
  readonly property var transformOptions: [
    { value: "0", label: "Normal" },
    { value: "1", label: "90°" },
    { value: "2", label: "180°" },
    { value: "3", label: "270°" },
    { value: "4", label: "Flipped" },
    { value: "5", label: "Flipped 90°" },
    { value: "6", label: "Flipped 180°" },
    { value: "7", label: "Flipped 270°" }
  ]

  onBrightnessConnectorChanged: {
    root.brightnessAvailable = false
    root.brightnessLoading = root.brightnessConnector !== ""
    if (root.opened) brightnessRuntime.selectionTimer.restart()
  }

  function open() {
    root.showPopup()
    root.cursorActive = false
    root.cursorIndex = 0
    root.checkBackend()
    root.checkServiceState()
    if (root.backendConnected) root.requestEditorState()
  }

  function openFromHotkey() { root.open() }
  function close() {
    if (root.previewTransaction !== "" && !root.previewCoordinator) root.revertPreview()
    root.keyboardHelpOpen = false
    root.execEditing = false
    root.hidePopup()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function brightnessName(percent) {
    var steps = [[95, "Sun blast"], [80, "Solar flare"], [65, "Golden hour"],
      [45, "Even day"], [30, "Soft glow"], [20, "Lamp light"], [10, "Candlelit"]]
    for (var index = 0; index < steps.length; index++)
      if (percent >= steps[index][0]) return steps[index][1]
    return "Night owl"
  }

  function displayError(message, fallback) {
    return String(message || fallback).replace(/hyprmoncfgd?/gi, "display service")
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshBrightness() {
    var connector = root.brightnessConnector
    if (!root.opened || connector === "") {
      root.brightnessLoading = false
      root.brightnessAvailable = false
      return
    }
    if (brightnessRuntime.readProcess.running || brightnessRuntime.setProcess.running) {
      root.brightnessReadQueued = true
      return
    }

    root.brightnessReadQueued = false
    root.brightnessReadConnector = connector
    if (!root.brightnessAvailable) root.brightnessLoading = true
    brightnessRuntime.readProcess.command = ["hyprshell", "system/monitor-brightness", "--monitor", connector]
    brightnessRuntime.readProcess.running = true
  }

  function previewBrightness(value) {
    if (root.brightnessConnector === "" || !root.brightnessAvailable) return
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessRuntime.setDebounce.restart()
  }

  function setTextSize(index) {
    var bounded = Math.max(0, Math.min(root.textSizes.length - 1, Math.round(index)))
    shell.run(["hyprshell", "system/text-size", String(root.textSizes[bounded])])
  }

  function startBrightnessSet(connector, percent) {
    if (connector === "") return
    root.brightnessSetConnector = connector
    brightnessRuntime.setProcess.command = [
      "hyprshell", "system/monitor-brightness", "--no-osd", "--monitor", connector, percent + "%"
    ]
    brightnessRuntime.setProcess.running = true
  }

  function setBrightness(value) {
    var connector = root.brightnessConnector
    if (connector === "" || !root.brightnessAvailable) return
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent
    root.pendingBrightnessConnector = connector

    if (brightnessRuntime.setProcess.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    root.startBrightnessSet(connector, percent)
  }

  function checkBackend() {
    if (backendRuntime.whichProcess.running) return
    backendRuntime.whichProcess.command = [
      "sh", "-c", "command -v hyprmoncfg >/dev/null 2>&1 && hyprmoncfg version"
    ]
    backendRuntime.whichProcess.running = true
  }

  function checkServiceState() {
    if (backendRuntime.serviceProcess.running || backendRuntime.enabledProcess.running
        || backendRuntime.activeProcess.running) return
    backendRuntime.enabledProcess.command = ["hyprshell", "system/monitor-profile", "service-enabled"]
    backendRuntime.enabledProcess.running = true
  }

  function setManaged(enabled) {
    if (backendRuntime.serviceProcess.running || root.serviceActionPending) return
    root.lastError = ""
    root.serviceActionPending = true
    root.serviceTargetManaged = enabled === true
    root.serviceAction = enabled === true ? "enable" : "disable"
    backendRuntime.serviceProcess.command = ["hyprshell", "system/monitor-profile", enabled === true ? "manage" : "unmanage"]
    backendRuntime.serviceProcess.running = true
  }

  function restartService() {
    if (backendRuntime.serviceProcess.running || root.serviceActionPending) return
    root.lastError = ""
    root.serviceActionPending = true
    root.serviceTargetManaged = true
    root.serviceAction = "restart"
    backendRuntime.serviceProcess.command = ["hyprshell", "system/monitor-profile", "restart"]
    backendRuntime.serviceProcess.running = true
  }

  function connectBackend() {
    if (backendRuntime.socket.connected || root.socketPath === "/hyprmoncfgd.sock") return
    if (!root.serviceEnabled && !root.serviceActive && !(root.serviceActionPending && root.serviceTargetManaged)) return
    backendRuntime.socket.connected = true
  }

  function send(method, params, context) {
    if (!backendRuntime.socket.connected) return ""
    root.requestSequence++
    var id = String(root.requestSequence)
    var request = {
      type: "request",
      protocol_version: 1,
      id: id,
      method: method
    }
    if (params !== undefined && params !== null) request.params = params
    root.pendingMethods[id] = method
    if (context !== undefined && context !== null) root.pendingContexts[id] = context
    backendRuntime.socket.write(JSON.stringify(request) + "\n")
    backendRuntime.socket.flush()
    return id
  }

  function subscribe() { root.send("subscribe", {}) }

  function requestEditorState() {
    if (!root.backendConnected || root.editorLoading || root.previewTransaction !== "") return
    root.editorLoading = true
    root.send("editor_state", {})
  }

  function updateEditor(value) {
    if (!Model.validEditorDocument(value)) {
      root.editorLoading = false
      root.lastError = "The display service returned an invalid editor state."
      return
    }
    root.editorDocument = value
    root.draftProfile = Model.clone(value.profile)
    root.workspacePlan = value.workspace_plan instanceof Array ? value.workspace_plan : []
    var workspaceSettings = (root.draftProfile || {}).workspaces || {}
    root.manualWorkspaceRulesInitialized = String(workspaceSettings.strategy || "") === "manual"
      && workspaceSettings.rules instanceof Array && workspaceSettings.rules.length > 0
    root.sourceProfile = String(value.source_profile || "")
    root.suggestedProfile = String(value.suggested_profile || "")
    root.selectedOutputKey = Model.initialOutputKey(root.draftProfile, value.displays)
    root.profileChoice = root.activeProfile !== "" ? root.activeProfile : root.suggestedProfile
    root.selectedSavedProfileName = root.profileChoice !== ""
      ? root.profileChoice
      : (value.profiles instanceof Array && value.profiles.length > 0 ? String(value.profiles[0].name || "") : "")
    root.saveName = root.sourceProfile
    root.editorReady = true
    root.editorLoading = false
    root.editPending = false
    root.draftDirty = false
    root.creatingProfile = false
    Qt.callLater(function() {
      root.normalizeWorkspaceCursor()
      if (root.activePage === "workspaces") root.ensureManualWorkspaceRules()
    })
  }

  function editDraft(edit) {
    if (!root.managedChecked || !root.editorReady || root.editPending || root.previewTransaction !== "") return
    root.lastError = ""
    root.editPending = true
    root.send("edit_profile", { profile: root.draftProfile, edit: edit })
  }

  function editOutput(fields, key) {
    var edit = fields || {}
    edit.output_key = String(key || root.selectedOutputKey)
    root.editDraft(edit)
  }

  function editWorkspaces(fields) {
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    var changes = fields || {}
    for (var key in changes) settings[key] = changes[key]
    root.editDraft({ workspaces: settings })
  }

  function changeWorkspaceStrategy(value) {
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    var current = String(settings.strategy || "manual")
    var next = String(value || "manual")
    var changes = { strategy: next }
    if (next === "manual" && current !== "manual" && !root.manualWorkspaceRulesInitialized) {
      changes.rules = Model.manualWorkspaceRulesFromPlan(root.workspacePlan, root.draftProfile)
      root.manualWorkspaceRulesInitialized = changes.rules.length > 0
    }
    root.editWorkspaces(changes)
  }

  function setWorkspaceCount(value) {
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    var maximum = Math.floor(root.bounded(Number(value || 1), 1, root.workspaceValueMaximum))
    if (String(settings.strategy || "") === "manual") {
      root.editWorkspaces({
        max_workspaces: maximum,
        rules: Model.resizeManualWorkspaceRules(settings.rules, root.draftProfile, maximum)
      })
      root.manualWorkspaceRulesInitialized = true
      return
    }
    root.editWorkspaces({ max_workspaces: maximum })
  }

  function moveManualWorkspace(row, delta) {
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    root.workspaceKeyboardIndex = root.workspaceListKeyboardStart + Number(row || 0)
    root.editWorkspaces({
      rules: Model.cycleManualWorkspaceRule(settings.rules, root.draftProfile, row, delta)
    })
    root.manualWorkspaceRulesInitialized = true
  }

  function ensureManualWorkspaceRules() {
    if (!root.managedChecked || !root.editorReady || root.editPending
        || root.previewTransaction !== "") return
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    if (String(settings.strategy || "") !== "manual"
        || (settings.rules instanceof Array && settings.rules.length > 0)) return
    var rules = Model.manualWorkspaceRulesFromPlan(root.workspacePlan, root.draftProfile)
    if (rules.length === 0) return
    root.manualWorkspaceRulesInitialized = true
    root.editWorkspaces({ rules: rules })
  }

  function moveWorkspaceMonitor(key, delta) {
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    var order = settings.monitor_order instanceof Array ? settings.monitor_order.slice() : []
    var index = order.indexOf(String(key || ""))
    var target = index + Number(delta || 0)
    if (index < 0 || target < 0 || target >= order.length) return
    var moved = order[index]
    order[index] = order[target]
    order[target] = moved
    root.editWorkspaces({ monitor_order: order })
  }

  function selectOutput(delta) {
    var next = Model.adjacentOutputKey(root.draftProfile, root.selectedOutputKey, delta)
    if (next !== "") root.selectedOutputKey = next
  }

  function nudgeSelectedOutput(dx, dy) {
    var output = root.selectedOutput
    if (!output || !root.managedChecked || root.editPending || root.previewTransaction !== "") return
    if (String(output.mirror_of || "") !== "") {
      root.lastError = String(output.name || "This display") + " mirrors another display and follows it."
      return
    }
    root.editOutput({
      x: Number(output.x || 0) + Number(dx || 0),
      y: Number(output.y || 0) + Number(dy || 0)
    })
  }

  function snapSelectedOutput(direction) {
    if (!root.managedChecked || root.editPending || root.previewTransaction !== "") return
    var position = Model.snapOutputPosition(root.draftProfile, root.selectedOutputKey, direction)
    if (!position) {
      root.lastError = "No other enabled display is available for snapping."
      return
    }
    root.editOutput({ x: position.x, y: position.y })
  }

  function cycleLayoutKeyboardPane(direction) {
    var panes = ["canvas", "display", "color"]
    var current = panes.indexOf(root.keyboardLayoutPane)
    root.keyboardLayoutPane = panes[Model.wrapIndex(current + direction, panes.length)]
    if (root.keyboardLayoutPane !== "canvas") {
      root.inspectorPage = root.keyboardLayoutPane
      var fields = root.keyboardLayoutPane === "display"
        ? root.displayKeyboardFields : root.colorKeyboardFields
      if (fields.indexOf(root.keyboardInspectorField) < 0)
        root.keyboardInspectorField = fields[0]
    }
  }

  function moveInspectorCursor(delta) {
    var fields = root.inspectorPage === "display"
      ? root.displayKeyboardFields : root.colorKeyboardFields
    var current = fields.indexOf(root.keyboardInspectorField)
    root.keyboardInspectorField = fields[Model.wrapIndex(current + delta, fields.length)]
  }

  function inspectorHasCursor(field) {
    return root.expanded && root.activePage === "layout"
      && root.keyboardLayoutPane !== "canvas"
      && root.keyboardInspectorField === field
  }

  function bounded(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function adjustInspectorField(delta) {
    var output = root.selectedOutput
    if (!output || !root.managedChecked || root.editPending || root.previewTransaction !== "") return
    var field = root.keyboardInspectorField
    var edit = ({})
    if (field === 0) edit.enabled = output.enabled === false
    else if (field === 1) edit.mode = Model.cycleOptionValue(
      Model.modeOptions(root.editorDocument.displays, root.selectedOutputKey), Model.outputMode(output), delta)
    else if (field === 2) edit.scale = root.bounded(Number(output.scale || 1) + delta * 0.05, 0.25, 4)
    else if (field === 3) edit.bitdepth = Number(Model.cycleOptionValue(root.bitdepthOptions,
      String(output.bitdepth || 8), delta))
    else if (field === 4) edit.cm = Model.cycleOptionValue(root.colorManagementOptions,
      String(output.cm || "srgb"), delta)
    else if (field === 5) edit.vrr = Number(Model.cycleOptionValue(root.vrrOptions,
      String(output.vrr || 0), delta))
    else if (field === 6) edit.transform = Number(Model.cycleOptionValue(root.transformOptions,
      String(output.transform || 0), delta))
    else if (field === 7) edit.x = Number(output.x || 0) + delta * 10
    else if (field === 8) edit.y = Number(output.y || 0) + delta * 10
    else if (field === 9) edit.mirror_of = Model.cycleOptionValue(
      Model.mirrorOptions(root.draftProfile, root.selectedOutputKey), String(output.mirror_of || ""), delta)
    else if (field === 10) edit.sdr_brightness = root.bounded(Number(output.sdr_brightness || 0) + delta * 0.05, 0, 3)
    else if (field === 11) edit.sdr_saturation = root.bounded(Number(output.sdr_saturation || 0) + delta * 0.05, 0, 3)
    else if (field === 12) edit.sdr_min_luminance = root.bounded(Number(output.sdr_min_luminance || 0) + delta * 0.005, 0, 1)
    else if (field === 13) edit.sdr_max_luminance = root.bounded(Number(output.sdr_max_luminance || 0) + delta * 10, 0, 1000)
    else if (field === 14) edit.sdr_eotf = Model.cycleOptionValue(displayView.sdrCurveMenu.options,
      String(output.sdr_eotf || "default"), delta)
    else if (field === 15) edit.min_luminance = root.bounded(Number(output.min_luminance || 0) + delta * 0.001, 0, 1000)
    else if (field === 16) edit.max_luminance = root.bounded(Number(output.max_luminance || 0) + delta * 10, 0, 2000)
    else if (field === 17) edit.max_avg_luminance = root.bounded(Number(output.max_avg_luminance || 0) + delta * 10, 0, 2000)
    else if (field === 18) edit.supports_wide_color = Number(Model.cycleOptionValue(root.triStateOptions,
      String(output.supports_wide_color || 0), delta))
    else if (field === 19) edit.supports_hdr = Number(Model.cycleOptionValue(root.triStateOptions,
      String(output.supports_hdr || 0), delta))
    else return
    root.editOutput(edit)
  }

  function activateInspectorField() {
    if (!root.selectedOutput || !root.managedChecked || root.editPending) return
    var field = root.keyboardInspectorField
    if (field === 0) root.adjustInspectorField(1)
    else if (field === 1) displayView.modeMenu.open()
    else if (field === 2) displayView.scaleMenu.open()
    else if (field === 3) displayView.bitdepthMenu.open()
    else if (field === 4) displayView.colorManagementMenu.open()
    else if (field === 5) displayView.vrrMenu.open()
    else if (field === 6) displayView.rotationMenu.open()
    else if (field === 7) displayView.positionX.field.forceActiveFocus()
    else if (field === 8) displayView.positionY.field.forceActiveFocus()
    else if (field === 9) displayView.mirrorMenu.open()
    else if (field === 10) displayView.sdrBrightness.input.forceActiveFocus()
    else if (field === 11) displayView.sdrSaturation.input.forceActiveFocus()
    else if (field === 12) displayView.sdrMinLuminance.input.forceActiveFocus()
    else if (field === 13) displayView.sdrMaxLuminance.input.forceActiveFocus()
    else if (field === 14) displayView.sdrCurveMenu.open()
    else if (field === 15) displayView.minLuminance.input.forceActiveFocus()
    else if (field === 16) displayView.maxLuminance.input.forceActiveFocus()
    else if (field === 17) displayView.maxAverageLuminance.input.forceActiveFocus()
    else if (field === 18) displayView.forceWideMenu.open()
    else if (field === 19) displayView.forceHdrMenu.open()
    else if (field === 20) displayView.iccProfile.forceActiveFocus()
  }

  function selectSavedProfile(delta) {
    var profiles = root.editorDocument && root.editorDocument.profiles instanceof Array
      ? root.editorDocument.profiles : []
    var selected = Model.adjacentProfileName(profiles, root.selectedSavedProfileName, delta)
    if (selected !== "") root.selectedSavedProfileName = selected
  }

  function loadSelectedSavedProfile() {
    if (!root.selectedSavedProfile) return
    root.draftProfile = Model.clone(root.selectedSavedProfile)
    root.workspacePlan = Model.clone(root.selectedSavedWorkspacePlan) || []
    var workspaceSettings = (root.draftProfile || {}).workspaces || {}
    root.manualWorkspaceRulesInitialized = String(workspaceSettings.strategy || "") === "manual"
      && workspaceSettings.rules instanceof Array && workspaceSettings.rules.length > 0
    root.sourceProfile = root.selectedSavedProfileName
    root.saveName = root.selectedSavedProfileName
    root.selectedOutputKey = Model.initialOutputKey(root.draftProfile, root.editorDocument.displays)
    root.draftDirty = true
    root.creatingProfile = false
    root.activePage = "layout"
    root.keyboardLayoutPane = "canvas"
    root.lastError = ""
  }

  function deleteSelectedSavedProfile() {
    var name = String(root.selectedSavedProfileName || "")
    if (name === "" || root.previewTransaction !== "") return
    root.lastError = ""
    root.send("delete", { name: name }, { name: name })
  }

  function beginExecEdit() {
    if (!root.selectedSavedProfile) return
    root.execDraft = String(root.selectedSavedProfile.exec || "")
    root.execEditing = true
    Qt.callLater(function() { displayView.profileExecField.forceActiveFocus() })
  }

  function commitExecEdit() {
    if (!root.selectedSavedProfile) {
      root.execEditing = false
      return
    }
    var profile = Model.clone(root.selectedSavedProfile)
    profile.exec = String(root.execDraft || "").trim()
    root.execEditing = false
    root.send("save", { profile: profile }, { kind: "exec", name: profile.name })
    Qt.callLater(function() { displayView.keyTarget.forceActiveFocus() })
  }

  function workspaceKeyboardCount() {
    var settings = ((root.draftProfile || {}).workspaces || {})
    if (root.workspaceStrategy === "manual")
      return root.workspaceListKeyboardStart + root.manualWorkspaceRows.length
    var order = settings.monitor_order || []
    return root.workspaceListKeyboardStart + order.length
  }

  function normalizeWorkspaceCursor() {
    root.workspaceKeyboardIndex = Model.wrapIndex(
      root.workspaceKeyboardIndex, root.workspaceKeyboardCount())
    if (displayView.workspaceAssignments.visible
        && root.workspaceKeyboardIndex >= root.workspaceListKeyboardStart)
      displayView.workspaceAssignments.positionViewAtIndex(
        root.workspaceKeyboardIndex - root.workspaceListKeyboardStart, ListView.Contain)
  }

  function moveWorkspaceCursor(delta) {
    root.workspaceKeyboardIndex = Model.wrapIndex(
      root.workspaceKeyboardIndex + delta, root.workspaceKeyboardCount())
    if (displayView.workspaceAssignments.visible
        && root.workspaceKeyboardIndex >= root.workspaceListKeyboardStart)
      displayView.workspaceAssignments.positionViewAtIndex(
        root.workspaceKeyboardIndex - root.workspaceListKeyboardStart, ListView.Contain)
  }

  function adjustWorkspaceKeyboard(delta) {
    if (!root.managedChecked || root.editPending || root.previewTransaction !== "") return
    var settings = Model.clone((root.draftProfile || {}).workspaces || {}) || {}
    var index = root.workspaceKeyboardIndex
    if (index === 0) root.editWorkspaces({ enabled: !settings.enabled })
    else if (index === 1) root.changeWorkspaceStrategy(
      Model.cycleOptionValue(["manual", "sequential", "interleave"],
        String(settings.strategy || "manual"), delta))
    else if (index === 2) root.setWorkspaceCount(
      (String(settings.strategy || "") === "manual"
        ? Model.manualWorkspaceCount(settings)
        : Number(settings.max_workspaces || 9)) + delta)
    else if (index === 3 && root.workspaceGroupSizeApplicable) {
      root.editWorkspaces({
        group_size: Math.floor(root.bounded(Number(settings.group_size || 3) + delta,
          1, root.workspaceValueMaximum))
      })
    }
    else {
      if (String(settings.strategy || "") === "manual") {
        root.moveManualWorkspace(index - root.workspaceListKeyboardStart, delta)
        return
      }
      var order = settings.monitor_order instanceof Array ? settings.monitor_order : []
      var orderIndex = index - root.workspaceListKeyboardStart
      var target = orderIndex + delta
      if (orderIndex < 0 || orderIndex >= order.length || target < 0 || target >= order.length) return
      root.moveWorkspaceMonitor(String(order[orderIndex] || ""), delta)
      root.workspaceKeyboardIndex = root.workspaceListKeyboardStart + target
    }
  }

  function draftName() {
    return root.sourceProfile !== "" ? root.sourceProfile : String(root.saveName || "").trim()
  }

  function previewCoordinatorReady(method) {
    return !!root.previewCoordinator
      && root.previewCoordinator.connected === true
      && root.previewCoordinator.yieldingToPanel !== true
      && typeof root.previewCoordinator[method] === "function"
  }

  function yieldPreviewToPanel() {
    if (root.previewCoordinator
        && typeof root.previewCoordinator.yieldToPanel === "function")
      root.previewCoordinator.yieldToPanel()
  }

  function previewDraft() {
    if (!root.managedChecked) return
    var name = root.draftName()
    if (name === "") {
      root.lastError = "Give this layout a profile name before previewing it."
      return
    }
    root.lastError = ""
    root.previewPending = true
    if (root.previewCoordinatorReady("startDraftPreview")) {
      if (!root.previewCoordinator.startDraftPreview(
          Model.namedProfile(root.draftProfile, name), 10)) {
        root.previewPending = false
        root.lastError = String(root.previewCoordinator.errorMessage
          || "Could not open the display confirmation.")
      }
      return
    }
    root.yieldPreviewToPanel()
    root.send("preview", {
      profile: Model.namedProfile(root.draftProfile, name),
      timeout_seconds: 10,
      save_on_commit: true
    }, { kind: "draft" })
  }

  function applyDraft() {
    if (!root.managedChecked || root.previewTransaction !== "" || root.previewPending) return
    var name = root.draftName() || "draft"
    var profile = Model.namedProfile(root.draftProfile, name)
    root.lastError = ""
    root.previewPending = true
    if (root.previewCoordinatorReady("startDraftApply")) {
      if (!root.previewCoordinator.startDraftApply(profile, 10)) {
        root.previewPending = false
        root.lastError = String(root.previewCoordinator.errorMessage
          || "Could not open the display confirmation.")
      }
      return
    }
    root.yieldPreviewToPanel()
    root.send("preview", {
      profile: profile,
      timeout_seconds: 10,
      save_on_commit: false
    }, { kind: "draft-apply" })
  }

  function keyboardSaveDraft() {
    if (root.draftName() !== "") {
      root.previewDraft()
      return
    }
    root.creatingProfile = true
    root.saveName = ""
    Qt.callLater(function() { displayView.profileNameField.forceActiveFocus() })
  }

  function handleExpandedMove(dx, dy) {
    if (root.keyboardHelpOpen) {
      root.keyboardHelpOpen = false
      return
    }
    if (root.previewTransaction !== "") return
    if (root.activePage === "layout") {
      if (root.keyboardLayoutPane === "canvas") root.nudgeSelectedOutput(dx * 100, dy * 100)
      else if (dy !== 0) root.moveInspectorCursor(dy)
      else if (dx !== 0) root.adjustInspectorField(dx)
    } else if (root.activePage === "profiles") {
      if (dy !== 0) root.selectSavedProfile(dy)
    } else if (root.activePage === "workspaces") {
      if (dy !== 0) root.moveWorkspaceCursor(dy)
      else if (dx !== 0) root.adjustWorkspaceKeyboard(dx)
    }
  }

  function handleExpandedActivate(returnPressed) {
    if (root.keyboardHelpOpen) {
      root.keyboardHelpOpen = false
      return
    }
    if (root.previewTransaction !== "") {
      root.keepPreview()
      return
    }
    if (root.activePage === "layout") {
      if (root.keyboardLayoutPane === "canvas") {
        if (returnPressed) root.cycleLayoutKeyboardPane(1)
        else if (root.selectedOutput) root.editOutput({ enabled: root.selectedOutput.enabled === false })
      } else root.activateInspectorField()
    } else if (root.activePage === "profiles") {
      if (returnPressed) root.activateSelectedSavedProfile()
      else root.setProfileAutomatic(!root.profileAutomatic)
    } else if (root.activePage === "workspaces") {
      root.adjustWorkspaceKeyboard(1)
    }
  }

  function handleExpandedTab(direction) {
    if (root.keyboardHelpOpen) {
      root.keyboardHelpOpen = false
      return
    }
    if (root.activePage === "layout") root.cycleLayoutKeyboardPane(direction)
  }

  function handleExpandedText(text) {
    var key = String(text || "")
    if (root.keyboardHelpOpen) {
      root.keyboardHelpOpen = false
      return
    }
    if (root.previewTransaction !== "") {
      if (key === "y" || key === "Y") root.keepPreview()
      else if (key === "n" || key === "N") root.revertPreview()
      return
    }
    if (key === "1" || key === "2" || key === "3") {
      root.activePage = key === "1" ? "layout" : (key === "2" ? "profiles" : "workspaces")
      return
    }
    if (key === "?") {
      root.keyboardHelpOpen = true
      return
    }
    if (key === "q") {
      root.close()
      return
    }
    if (key === "R") {
      if (root.daemonOutdated) root.restartService()
      return
    }
    if (key === "r") {
      root.requestEditorState()
      return
    }
    if (key === "s") {
      root.keyboardSaveDraft()
      return
    }
    if (key === "a") {
      if (root.activePage === "profiles") root.activateSelectedSavedProfile()
      else root.applyDraft()
      return
    }

    if (root.activePage === "layout") {
      if (key === "0") root.editOutput({ x: 0, y: 0 })
      else if (key === "[") root.selectOutput(-1)
      else if (key === "]") root.selectOutput(1)
      else if (root.keyboardLayoutPane === "canvas" && key === "H") root.nudgeSelectedOutput(-500, 0)
      else if (root.keyboardLayoutPane === "canvas" && key === "L") root.nudgeSelectedOutput(500, 0)
      else if (root.keyboardLayoutPane === "canvas" && key === "K") root.nudgeSelectedOutput(0, -500)
      else if (root.keyboardLayoutPane === "canvas" && key === "J") root.nudgeSelectedOutput(0, 500)
      else if (root.keyboardLayoutPane !== "canvas" && (key === "-" || key === "_")) root.adjustInspectorField(-1)
      else if (root.keyboardLayoutPane !== "canvas" && (key === "+" || key === "=")) root.adjustInspectorField(1)
    } else if (root.activePage === "profiles") {
      if (key === "e") root.beginExecEdit()
      else if (key === "d") root.deleteSelectedSavedProfile()
    } else if (root.activePage === "workspaces") {
      if (key === "-" || key === "_") root.adjustWorkspaceKeyboard(-1)
      else if (key === "+" || key === "=") root.adjustWorkspaceKeyboard(1)
    }
  }

  function previewProfile(name) {
    var selected = String(name || root.profileChoice || "")
    if (selected === "") return
    if (!root.managedChecked) return
    if (root.profileAutomatic) {
      root.lastError = "Turn off automatic profile selection before activating a profile."
      return
    }
    root.lastError = ""
    root.previewPending = true
    if (root.previewCoordinatorReady("startSavedProfilePreview")) {
      if (!root.previewCoordinator.startSavedProfilePreview(selected, 10)) {
        root.previewPending = false
        root.lastError = String(root.previewCoordinator.errorMessage
          || "Could not open the display confirmation.")
      }
      return
    }
    root.yieldPreviewToPanel()
    root.send("preview", { profile_name: selected, timeout_seconds: 10 }, {
      kind: "profile",
      name: selected
    })
  }

  function activateSelectedSavedProfile() {
    var selected = String(root.selectedSavedProfileName || "")
    if (selected === "" || selected === root.activeProfile) return
    root.profileChoice = selected
    root.previewProfile(selected)
  }

  function setProfileAutomatic(enabled) {
    if (!root.managedChecked || !root.backendConnected || root.profileModePending || root.previewTransaction !== "") return
    root.lastError = ""
    if (enabled && root.activeProfile !== "") {
      root.profileChoice = root.activeProfile
      root.selectedSavedProfileName = root.activeProfile
    }
    root.profileModePending = true
    root.send("set_profile_auto", { enabled: enabled })
  }

  function beginCreateProfile() {
    if (!root.managedChecked || !root.editorReady || root.previewTransaction !== "" || root.previewPending) return
    root.lastError = ""
    root.sourceProfile = ""
    root.saveName = ""
    root.creatingProfile = true
    root.activePage = "layout"
    root.expanded = true
    Qt.callLater(function() { displayView.profileNameField.forceActiveFocus() })
  }

  function keepPreview() {
    if (root.previewTransaction === "" || root.previewPending) return
    root.previewPending = true
    if (root.previewCoordinator
        && String(root.previewCoordinator.transactionId || "") === root.previewTransaction) {
      if (!root.previewCoordinator.keep()) root.previewPending = false
      return
    }
    root.send("commit", {
      transaction_id: root.previewTransaction,
      save: root.previewKind === "draft"
    }, { kind: root.previewKind })
  }

  function revertPreview() {
    if (root.previewTransaction === "" || root.previewPending) return
    root.previewPending = true
    if (root.previewCoordinator
        && String(root.previewCoordinator.transactionId || "") === root.previewTransaction) {
      if (!root.previewCoordinator.revert()) root.previewPending = false
      return
    }
    root.send("revert", { transaction_id: root.previewTransaction }, { kind: root.previewKind })
  }

  function clearPreview(reload) {
    root.previewTransaction = ""
    root.previewKind = ""
    root.previewDeadline = ""
    root.previewSeconds = 0
    root.previewPending = false
    previewTimer.stop()
    if (reload) root.requestEditorState()
  }

  function updatePreviewClock() {
    var deadline = Date.parse(root.previewDeadline)
    if (!isFinite(deadline)) return
    root.previewSeconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000))
    if (root.previewSeconds === 0) root.clearPreview(true)
  }

  function updateDocument(value) {
    if (!value || typeof value !== "object") return
    root.document = value
    root.documentReady = true
    root.syncDaemonPreview(value.daemon ? value.daemon.preview : null)
    if (root.serviceActionPending) {
      var unmanaged = !!(value.daemon && value.daemon.unmanaged)
      if (root.serviceTargetManaged === !unmanaged) {
        root.serviceActionPending = false
        root.serviceAction = ""
        backendRuntime.serviceConfirmationTimer.stop()
      }
    }
  }

  function syncDaemonPreview(pending) {
    var id = pending ? String(pending.transaction_id || "") : ""
    if (id !== "") {
      root.previewTransaction = id
      root.previewKind = pending.save_on_commit ? "draft" : "profile"
      root.previewDeadline = String(pending.deadline || "")
      root.previewPending = false
      if (pending.profile && pending.profile.outputs instanceof Array) {
        root.draftProfile = Model.clone(pending.profile)
        root.profileChoice = String(pending.profile_name || pending.profile.name || "")
        root.selectedSavedProfileName = root.profileChoice
      }
      root.updatePreviewClock()
      previewTimer.start()
      if ((!root.previewCoordinator || !root.previewCoordinator.connected
          || root.previewCoordinator.yieldingToPanel)
          && !root.opened && !previewRecoveryTimer.running)
        previewRecoveryTimer.start()
      return
    }
    if (root.previewTransaction !== "" && !root.previewPending) root.clearPreview(false)
  }

  function handleMessage(line) {
    var envelope = Model.parseEnvelope(line)
    if (!envelope) {
      root.lastError = "The display service returned an invalid response."
      return
    }
    if (envelope.type === "event") {
      if (envelope.event === "status") root.updateDocument(envelope.data)
      return
    }

    var method = root.pendingMethods[String(envelope.id)] || ""
    var context = root.pendingContexts[String(envelope.id)] || ({})
    delete root.pendingMethods[String(envelope.id)]
    delete root.pendingContexts[String(envelope.id)]
    if (envelope.error) {
      if (method === "editor_state") root.editorLoading = false
      if (method === "edit_profile") root.editPending = false
      if (method === "preview" || method === "commit" || method === "revert") root.previewPending = false
      if (method === "set_profile_auto") root.profileModePending = false
      root.lastError = root.displayError(envelope.error.message, "Display service request failed")
      return
    }
    if (method === "status" || method === "subscribe") {
      root.updateDocument(envelope.result)
      if (method === "subscribe" && root.opened) root.requestEditorState()
    }
    else if (method === "editor_state") root.updateEditor(envelope.result)
    else if (method === "edit_profile") {
      var result = envelope.result || {}
      if (!result.profile || !(result.profile.outputs instanceof Array)) {
        root.editPending = false
        root.lastError = "The display service returned an invalid edited profile."
        return
      }
      root.draftProfile = result.profile
      root.workspacePlan = result.workspace_plan instanceof Array ? result.workspace_plan : []
      root.editPending = false
      root.draftDirty = true
      Qt.callLater(function() {
        root.normalizeWorkspaceCursor()
        if (root.activePage === "workspaces") root.ensureManualWorkspaceRules()
      })
    } else if (method === "preview") {
      var transaction = envelope.result || {}
      root.previewTransaction = String(transaction.id || "")
      root.previewKind = String(context.kind || "profile")
      root.previewDeadline = String(transaction.deadline || "")
      root.previewPending = false
      root.updatePreviewClock()
      previewTimer.start()
    } else if (method === "commit" || method === "revert") {
      root.clearPreview(true)
    } else if (method === "set_profile_auto") {
      root.profileModePending = false
    } else if (method === "save" || method === "delete") {
      root.requestEditorState()
    }
  }

  function itemCount() {
    return root.layoutRowIndex + 1
  }

  function moveCursor(delta) {
    root.cursorActive = true
    root.cursorIndex = Math.max(0, Math.min(root.itemCount() - 1, root.cursorIndex + delta))
  }

  function activateCursor() {
    if (root.cursorIndex === 0) {
      root.setManaged(!root.managedChecked)
      return
    }
    var row = root.actionRows[root.cursorIndex - 1]
    if (row) {
      root.activateRow(String(row.id))
      return
    }
    root.expanded = true
  }

  function activateRow(id) {
    if (id === "restart-service") root.restartService()
  }

  Component.onCompleted: {
    Style.shell = root.shell
    Color.shell = root.shell
    root.checkBackend()
  }
  onActivePageChanged: {
    if (root.activePage === "workspaces")
      Qt.callLater(function() { root.ensureManualWorkspaceRules() })
  }

  Connections {
    target: root.previewCoordinator
    ignoreUnknownSignals: true
    function onRequestFinished(success, message) {
      root.previewPending = false
      if (!success && String(message || "") !== "") root.lastError = String(message)
    }
  }

  onOpenedChanged: {
    if (opened) {
      root.cursorIndex = 0
      root.cursorActive = false
      root.keyboardLayoutPane = "canvas"
      root.keyboardInspectorField = 0
      root.workspaceKeyboardIndex = 0
      root.checkBackend()
      root.checkServiceState()
      if (root.backendConnected) root.requestEditorState()
      brightnessRuntime.selectionTimer.restart()
    } else {
      brightnessRuntime.setDebounce.stop()
    }
  }

  DisplayBackend { id: backendRuntime; controller: root }

  DisplayBrightnessBackend { id: brightnessRuntime; controller: root }


  Timer {
    id: previewTimer
    interval: 250
    repeat: true
    onTriggered: root.updatePreviewClock()
  }

  // Applying a profile can rebuild the shell's per-screen bar and destroy the
  // panel that initiated the preview. The daemon keeps the transaction alive;
  // ask the shared bar host to reopen this widget on the focused output so the
  // replacement instance can show the same Keep/Revert choice.
  Timer {
    id: previewRecoveryTimer
    property int attempts: 0
    interval: 150
    repeat: true
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      attempts++
      if (root.previewTransaction === "" || root.opened) {
        stop()
        return
      }
      if (root.bar && typeof root.bar.summonBarWidget === "function")
        root.bar.summonBarWidget(root.moduleName)
      if (attempts >= 20) stop()
    }
  }

  DisplayView { id: displayView; controller: root }




}

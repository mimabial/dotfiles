import QtQuick
import Quickshell.Io

Item {
  id: runtime
  required property var controller
  property alias socket: backendSocket
  property alias versionProcess: versionProcess
  property alias managementCheckProcess: managementCheckProcess
  property alias daemonCheckProcess: daemonCheckProcess
  property alias serviceActionProcess: serviceActionProcess
  property alias serviceActionDeadline: serviceActionDeadline
  property bool serviceCheckQueued: false

  Socket {
    id: backendSocket
    path: runtime.controller.socketPath
    connected: false
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { runtime.controller.handleMessage(line) }
    }
    onConnectedChanged: {
      runtime.controller.connectionPending = false
      if (connected) {
        runtime.controller.lastError = ""
        runtime.controller.subscribe()
      } else {
        runtime.controller.pendingMethods = ({})
        runtime.controller.pendingContexts = ({})
        runtime.controller.editorReady = false
        runtime.controller.editorLoading = false
        runtime.controller.editPending = false
        runtime.controller.profileModePending = false
        runtime.controller.clearPreview(false)
      }
    }
    onError: {
      runtime.controller.connectionPending = false
      backendSocket.connected = false
    }
  }

  Connections {
    target: runtime.controller.previewCoordinator
    function onBackendChanged() { runtime.controller.checkServiceState() }
    function onConnectedChanged() {
      if (runtime.controller.previewCoordinator.connected) runtime.controller.connectBackend()
    }
  }

  Process {
    id: versionProcess
    stdout: StdioCollector { id: versionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      runtime.controller.backendVersion = exitCode === 0 ? String(versionOutput.text || "") : ""
      if (exitCode === 0) runtime.controller.checkServiceState()
      else {
        backendSocket.connected = false
        runtime.controller.serviceStateKnown = false
      }
    }
  }

  Process {
    id: managementCheckProcess
    onExited: function(exitCode) {
      runtime.controller.serviceEnabled = exitCode === 0
      daemonCheckProcess.command = [runtime.controller.monitorProfileHelper, "service-active"]
      daemonCheckProcess.running = true
    }
  }

  Process {
    id: daemonCheckProcess
    onExited: function(exitCode) {
      runtime.controller.serviceActive = exitCode === 0
      runtime.controller.serviceStateKnown = true
      if (runtime.controller.serviceActive) runtime.controller.connectBackend()
      else {
        runtime.controller.connectionPending = false
        backendSocket.connected = false
      }
      if (runtime.serviceCheckQueued) runtime.controller.checkServiceState()
    }
  }

  Process {
    id: serviceActionProcess
    stderr: StdioCollector { id: serviceErrorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var disabling = runtime.controller.serviceAction === "disable"
        runtime.controller.serviceActionPending = false
        runtime.controller.serviceAction = ""
        var fallback = disabling ? "Could not return display management to Hyprland." : "Could not start the display service."
        runtime.controller.lastError = runtime.controller.displayError(serviceErrorOutput.text, fallback).trim()
      } else if (runtime.controller.serviceActionPending) {
        serviceActionDeadline.restart()
        runtime.controller.send("status", {})
      }
      runtime.controller.checkServiceState()
    }
  }

  Timer {
    id: serviceActionDeadline
    interval: 5000
    onTriggered: {
      if (!runtime.controller.serviceActionPending) return
      runtime.controller.serviceActionPending = false
      runtime.controller.serviceAction = ""
      runtime.controller.lastError = "Could not confirm the automatic switching state."
    }
  }
}

import QtQuick
import Quickshell.Io

Item {
  id: runtime
  required property var controller
  property alias socket: backendSocket
  property alias whichProcess: whichProcess
  property alias enabledProcess: enabledProcess
  property alias activeProcess: activeProcess
  property alias serviceProcess: serviceProcess
  property alias serviceRefreshTimer: serviceRefreshTimer
  property alias connectionGraceTimer: connectionGraceTimer
  property alias serviceConfirmationTimer: serviceConfirmationTimer
  property alias reconnectTimer: reconnectTimer

  Socket {
    id: backendSocket
    path: runtime.controller.socketPath
    connected: false
    parser: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { runtime.controller.handleMessage(line) }
    }
    onConnectedChanged: {
      if (connected) {
        runtime.controller.connectionGrace = false
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
        if (runtime.controller.serviceEnabled || runtime.controller.serviceActive)
          serviceRefreshTimer.restart()
      }
    }
    onError: function(error) { backendSocket.connected = false }
  }
  
  Process {
    id: whichProcess
    stdout: StdioCollector { id: versionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      runtime.controller.backendVersion = exitCode === 0 ? String(versionOutput.text || "") : ""
      if (exitCode === 0) {
        runtime.controller.checkServiceState()
      } else {
        backendSocket.connected = false
        runtime.controller.serviceStateKnown = false
      }
    }
  }
  
  Process {
    id: enabledProcess
    onExited: function(exitCode) {
      runtime.controller.serviceEnabled = exitCode === 0
      activeProcess.command = ["hyprshell", "system/monitor-profile", "service-active"]
      activeProcess.running = true
    }
  }
  
  Process {
    id: activeProcess
    onExited: function(exitCode) {
      var wasActive = runtime.controller.serviceActive
      runtime.controller.serviceActive = exitCode === 0
      runtime.controller.serviceStateKnown = true
      if (runtime.controller.serviceActive) {
        if (!runtime.controller.backendConnected) {
          if (!wasActive) {
            runtime.controller.connectionGrace = true
            connectionGraceTimer.restart()
          }
          runtime.controller.connectBackend()
        }
      } else {
        runtime.controller.connectionGrace = false
        backendSocket.connected = false
      }
      if (runtime.controller.serviceActionPending && !serviceProcess.running) {
        // Turning management off no longer stops the daemon, so only the
        // managed direction can be confirmed from its process state. The other one is
        // confirmed by the daemon's status document in updateDocument.
        var confirmed = runtime.controller.serviceTargetManaged
          && runtime.controller.serviceEnabled
          && runtime.controller.serviceActive
        if (confirmed) {
          runtime.controller.serviceActionPending = false
          runtime.controller.serviceAction = ""
          serviceConfirmationTimer.stop()
        } else {
          serviceRefreshTimer.restart()
        }
      }
    }
  }
  
  Process {
    id: serviceProcess
    stderr: StdioCollector { id: serviceStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var action = runtime.controller.serviceAction
      if (exitCode !== 0) {
        runtime.controller.serviceActionPending = false
        runtime.controller.serviceAction = ""
        var fallback = action === "disable" ? "Could not return display management to Hyprland." : "Could not start the display service."
        runtime.controller.lastError = runtime.controller.displayError(serviceStderr.text, fallback).trim()
      } else if (action === "disable") {
        runtime.controller.checkServiceState()
      } else {
        runtime.controller.connectionGrace = true
        connectionGraceTimer.restart()
        reconnectTimer.restart()
      }
      if (exitCode === 0) serviceConfirmationTimer.restart()
      serviceRefreshTimer.restart()
    }
  }

  Timer {
    id: serviceRefreshTimer
    interval: 250
    onTriggered: runtime.controller.checkServiceState()
  }
  
  Timer {
    id: serviceDiscoveryTimer
    interval: 2000
    repeat: true
    running: !runtime.controller.backendConnected && !runtime.controller.serviceActionPending
    onTriggered: runtime.controller.checkServiceState()
  }
  
  Timer {
    id: connectionGraceTimer
    interval: 2000
    onTriggered: runtime.controller.connectionGrace = false
  }
  
  Timer {
    id: serviceConfirmationTimer
    interval: 5000
    onTriggered: {
      if (!runtime.controller.serviceActionPending) return
      runtime.controller.serviceActionPending = false
      runtime.controller.serviceAction = ""
      runtime.controller.lastError = "Could not confirm the automatic switching state."
      runtime.controller.checkServiceState()
    }
  }
  
  Timer {
    id: reconnectTimer
    interval: 1000
    repeat: true
    running: (runtime.controller.serviceActive || (runtime.controller.serviceActionPending && runtime.controller.serviceTargetManaged))
      && !runtime.controller.backendConnected
    onTriggered: {
      runtime.controller.checkServiceState()
      runtime.controller.connectBackend()
    }
  }
}

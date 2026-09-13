import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: runtime
  required property var controller
  property alias selectionTimer: brightnessSelectionTimer
  property alias setDebounce: brightnessSetDebounce
  property alias readProcess: brightnessReadProcess
  property alias setProcess: brightnessSetProcess

  Timer {
    id: brightnessSelectionTimer
    interval: 80
    repeat: false
    onTriggered: runtime.controller.refreshBrightness()
  }
  
  Timer {
    id: brightnessSetDebounce
    interval: 180
    repeat: false
    onTriggered: runtime.controller.setBrightness(runtime.controller.brightnessPercent)
  }
  
  Timer {
    interval: 5000
    repeat: true
    running: runtime.controller.opened && runtime.controller.brightnessConnector !== ""
    onTriggered: runtime.controller.refreshBrightness()
  }
  
  Process {
    id: brightnessReadProcess
    stdout: StdioCollector { id: brightnessReadOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var connector = runtime.controller.brightnessReadConnector
      var parsed = Number(String(brightnessReadOutput.text || "").trim())
      if (connector === runtime.controller.brightnessConnector) {
        runtime.controller.brightnessLoading = false
        runtime.controller.brightnessAvailable = exitCode === 0 && isFinite(parsed)
        if (runtime.controller.brightnessAvailable) runtime.controller.brightnessPercent = Model.clampBrightness(parsed)
      }
      if (runtime.controller.brightnessReadQueued) {
        runtime.controller.brightnessReadQueued = false
        brightnessSelectionTimer.restart()
      }
    }
  }
  
  Process {
    id: brightnessSetProcess
    onExited: function(exitCode) {
      var completedConnector = runtime.controller.brightnessSetConnector
      if (exitCode !== 0 && completedConnector === runtime.controller.brightnessConnector) {
        runtime.controller.brightnessAvailable = false
      }
  
      if (runtime.controller.brightnessSetQueued) {
        runtime.controller.brightnessSetQueued = false
        if (runtime.controller.pendingBrightnessConnector === runtime.controller.brightnessConnector)
          runtime.controller.startBrightnessSet(runtime.controller.pendingBrightnessConnector, runtime.controller.pendingBrightnessPercent)
        return
      }
  
      if (runtime.controller.brightnessReadQueued) {
        runtime.controller.brightnessReadQueued = false
        // Avoid an immediate-read race after a successful write.
        // A new selection needs a read now; this display can wait for the
        // regular five-second reconciliation.
        if (completedConnector !== runtime.controller.brightnessConnector || exitCode !== 0)
          brightnessSelectionTimer.restart()
      }
    }
  }
}

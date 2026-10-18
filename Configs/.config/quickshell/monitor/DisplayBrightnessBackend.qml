import QtQuick
import Quickshell.Io
import qs as Bar
import "Model.js" as Model

Item {
  id: runtime
  required property var controller
  property alias readProcess: brightnessReadProcess
  property alias setProcess: brightnessSetProcess

  function writePendingBrightness() {
    if (!controller.brightnessSetQueued) return false
    controller.brightnessSetQueued = false
    if (controller.pendingBrightnessConnector !== controller.brightnessConnector) return false
    controller.startBrightnessSet(controller.pendingBrightnessConnector, controller.pendingBrightnessPercent)
    return true
  }

  Connections {
    target: Bar.Backlight
    function onRawChanged() { runtime.controller.refreshBrightness() }
    function onDeviceChanged() { runtime.controller.refreshBrightness() }
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
        if (runtime.controller.brightnessAvailable && !runtime.controller.brightnessSetQueued)
          runtime.controller.brightnessPercent = Model.clampBrightness(parsed)
      }
      if (runtime.writePendingBrightness()) return
      if (runtime.controller.brightnessReadQueued) runtime.controller.refreshBrightness()
    }
  }

  Process {
    id: brightnessSetProcess
    onExited: function(exitCode) {
      if (exitCode !== 0 && runtime.controller.brightnessSetConnector === runtime.controller.brightnessConnector)
        runtime.controller.brightnessAvailable = false
      if (runtime.writePendingBrightness()) return
      if (runtime.controller.brightnessReadQueued) runtime.controller.refreshBrightness()
    }
  }
}

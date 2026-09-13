pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
  id: backend
  required property var controller
  required property var store
  required property BookmarkEditor editor
  required property BookmarkImport importer
  required property NetworkEnrichmentDialog networkDialog
  property alias statusTimer: statusTimer
  property alias quickAddProcess: quickAddProcess
  property alias copyProcess: copyProcess
  property alias networkStatusProcess: networkStatusProcess
  property alias networkSettingProcess: networkSettingProcess
  property alias importPickerProcess: importPickerProcess
  property alias firefoxSyncProcess: firefoxSyncProcess

  Timer {
    id: statusTimer
    interval: 5000
    repeat: false
    onTriggered: backend.controller.statusMessage = ""
  }
  
  Process {
    id: quickAddProcess
    running: false
    command: ["true"]
  
    onStarted: {
      backend.controller.quickAddResult = null
      backend.controller.quickAddResponseError = ""
    }
  
    stdout: SplitParser {
      onRead: function(data) {
        try {
          var output = String(data || "")
          if (output.length > backend.controller.maxQuickAddOutputCharacters)
            throw new Error("Clipboard helper returned too much data")
          backend.controller.quickAddResult = JSON.parse(output)
        } catch (exception) {
          backend.controller.quickAddResponseError = String(
            exception.message || "Could not add clipboard bookmark"
          )
        }
      }
    }
  
    onExited: function(exitCode) {
      backend.controller.quickAdding = false
      if (backend.controller.quickAddCanceled) {
        backend.controller.quickAddCanceled = false
        backend.controller.quickAddResult = null
        backend.controller.quickAddResponseError = ""
        return
      }
      var result = backend.controller.quickAddResult
      var responseError = backend.controller.quickAddResponseError
      backend.controller.quickAddResult = null
      backend.controller.quickAddResponseError = ""
      if (result) {
        if (exitCode !== 0 || !result.ok) {
          backend.controller.showStatus(String(result.error || "Could not add clipboard bookmark"))
        } else if (result.duplicate) {
          backend.controller.viewMode = 0
          backend.controller.query = ""
          backend.controller.selectBookmarkById(result.id)
          backend.controller.showStatus("That URL is already bookmarked")
        } else {
          backend.editor.openForClipboard(result.item)
        }
      } else {
        backend.controller.showStatus(responseError || "Could not add clipboard bookmark")
      }
      backend.controller.refocusList()
    }
  
    onRunningChanged: {
      if (!running && backend.controller.quickAdding) {
        var canceled = backend.controller.quickAddCanceled
        backend.controller.quickAdding = false
        backend.controller.quickAddCanceled = false
        backend.controller.quickAddResult = null
        backend.controller.quickAddResponseError = ""
        if (!canceled && backend.controller.opened) {
          backend.controller.showStatus("Could not start the clipboard helper")
          backend.controller.refocusList()
        }
      }
    }
  }
  
  Process {
    id: copyProcess
    running: false
    command: ["true"]
  
    onStarted: backend.controller.copyResponse = null
  
    stdout: SplitParser {
      onRead: function(data) {
        try {
          backend.controller.copyResponse = backend.controller.parseSmallHelperResponse(data)
        } catch (exception) {
          backend.controller.copyResponse = {ok: false, error: "Could not copy URL"}
        }
      }
    }
  
    onExited: function(exitCode) {
      var message = "Copied " + backend.controller.copyTargetTitle + " URL"
      var result = backend.controller.copyResponse
      backend.controller.copyResponse = null
      if (!result || exitCode !== 0 || !result.ok)
        message = String(result && result.error || "Could not copy URL")
      backend.controller.copyTargetTitle = ""
      if (backend.controller.opened) {
        backend.controller.showStatus(message)
        backend.controller.refocusList()
      }
    }
  
    onRunningChanged: {
      if (!running && backend.controller.copyTargetTitle) {
        backend.controller.copyResponse = null
        backend.controller.copyTargetTitle = ""
        if (backend.controller.opened) {
          backend.controller.showStatus("Could not start the clipboard helper")
          backend.controller.refocusList()
        }
      }
    }
  }
  
  Process {
    id: networkStatusProcess
    running: false
    command: ["true"]
  
    onStarted: backend.controller.networkStatusResponse = null
  
    stdout: SplitParser {
      onRead: function(data) {
        try {
          backend.controller.networkStatusResponse = backend.controller.parseSmallHelperResponse(data)
        } catch (exception) {
          backend.controller.networkStatusResponse = {
            ok: false,
            error: "Could not inspect web-details preference"
          }
        }
      }
    }
  
    onExited: function(exitCode) {
      var result = backend.controller.networkStatusResponse
      backend.controller.networkStatusResponse = null
      if (result && exitCode === 0 && result.ok) {
        backend.controller.networkEnrichmentEnabled = result.enabled === true
        backend.controller.networkSettingStateReady = true
      } else {
        backend.controller.networkEnrichmentEnabled = false
        backend.controller.networkSettingStateReady = false
        if (backend.controller.opened)
          backend.controller.showStatus(String(result && result.error || "Could not inspect web-details preference"))
      }
    }
  }
  Process {
    id: networkSettingProcess
    running: false
    command: ["true"]
  
    onStarted: backend.controller.networkSettingResponse = null
  
    stdout: SplitParser {
      onRead: function(data) {
        try {
          backend.controller.networkSettingResponse = backend.controller.parseSmallHelperResponse(data)
        } catch (exception) {
          backend.controller.networkSettingResponse = {
            ok: false,
            error: "Could not save web-details preference"
          }
        }
      }
    }
  
    onExited: function(exitCode) {
      try {
        var result = backend.controller.networkSettingResponse
        backend.controller.networkSettingResponse = null
        if (!result)
          throw new Error("Could not save web-details preference")
        if (exitCode !== 0 || !result.ok)
          throw new Error(String(result.error || "Could not save web-details preference"))
        backend.controller.networkEnrichmentEnabled = result.enabled === true
        backend.controller.networkSettingStateReady = true
        backend.controller.networkDialogOpen = false
        if (backend.controller.opened) {
          backend.controller.showStatus(
            backend.controller.networkEnrichmentEnabled
              ? "Web details enabled for future pasted URLs"
              : "Web details disabled · pasting will not access the network"
          )
          if (backend.editor.opened)
            backend.editor.refocus()
          else
            backend.controller.refocusList()
        }
      } catch (exception) {
        backend.networkDialog.errorMessage = String(
          exception.message || "Could not save web-details preference"
        )
      }
      backend.controller.networkSettingOperation = ""
    }
  
    onRunningChanged: {
      if (!running && backend.controller.networkSettingOperation) {
        backend.controller.networkSettingResponse = null
        backend.controller.networkSettingOperation = ""
        backend.networkDialog.errorMessage = "Could not start the settings helper"
      }
    }
  }
  
  Process {
    id: importPickerProcess
    running: false
    command: ["true"]
  
    onStarted: backend.controller.importPickerPath = ""
  
    stdout: SplitParser {
      onRead: function(data) {
        var path = String(data || "").trim()
        backend.controller.importPickerPath = path.length <= 4096 ? path : ""
      }
    }
  
    onExited: function(exitCode) {
      backend.controller.fileDialogOpen = false
      var path = backend.controller.importPickerPath
      backend.controller.importPickerPath = ""
      if (exitCode === 0 && path)
        backend.importer.begin(path)
      else {
        backend.controller.refocusList()
      }
    }
  
    onRunningChanged: {
      if (!running && backend.controller.fileDialogOpen) {
        backend.controller.importPickerPath = ""
        backend.controller.fileDialogOpen = false
        if (backend.controller.opened) {
          backend.controller.showStatus("Could not open import picker · install Zenity")
          backend.controller.refocusList()
        }
      }
    }
  }

  Process {
    id: firefoxSyncProcess
    running: false
    command: ["true"]
  
    stdout: SplitParser {
      onRead: function(data) {
        try {
          backend.controller.firefoxSyncResponse = backend.controller.parseSmallHelperResponse(data)
        } catch (exception) {
          backend.controller.firefoxSyncResponse = {
            ok: false,
            error: "Invalid Firefox sync response"
          }
        }
      }
    }
  
    onExited: function(exitCode) {
      var response = backend.controller.firefoxSyncResponse
      backend.controller.firefoxSyncResponse = null
      if (exitCode !== 0 || !response || !response.ok) {
        backend.controller.showStatus(
          "Firefox sync failed"
          + (response && response.error ? " · " + response.error : "")
        )
        return
      }
      var stats = response.stats || ({})
      var changes = Number(stats.changed || 0)
      backend.controller.showStatus(
        changes
          ? "Firefox synced · "
            + Number(stats.new || 0) + " added · "
            + Number(stats.updated || 0) + " updated · "
            + Number(stats.removed || 0) + " removed"
          : "Firefox bookmarks are up to date"
      )
      backend.store.reload()
    }
  }
}

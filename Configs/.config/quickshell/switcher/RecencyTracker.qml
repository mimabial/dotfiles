pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Quickshell.Hyprland
import "Recency.js" as Recency

Item {
  id: tracker

  property var recencyState: Recency.createState()
  property bool seeded: false

  signal windowClosed(string address)

  function trackedCount() {
    return Object.keys(tracker.recencyState.lastActive).length
  }

  function seedFromToplevels() {
    const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    const clients = []
    for (let i = 0; i < toplevels.length; i++) {
      const toplevel = toplevels[i]
      const ipc = toplevel ? toplevel.lastIpcObject : null
      if (!ipc || ipc.focusHistoryID === undefined) continue
      clients.push({ address: toplevel.address, focusHistoryID: ipc.focusHistoryID })
    }
    const count = Recency.seedFromClients(tracker.recencyState, clients, Date.now())
    if (clients.length > 0) tracker.seeded = true
    return count
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Qt.callLater(tracker.seedFromToplevels)
  }


  Instantiator {
    model: Hyprland.toplevels.values
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { tracker.seedFromToplevels() }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { tracker.seedFromToplevels() }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      const name = event.name
      if (name === "activewindowv2") Recency.recordFocus(tracker.recencyState, event.data, Date.now())
      else if (name === "openwindow") Recency.recordOpen(tracker.recencyState, event.data, Date.now())
      else if (name === "closewindow") {
        if (Recency.recordClose(tracker.recencyState, event.data))
          tracker.windowClosed(Recency.firstField(event.data))
      }
    }
  }
}

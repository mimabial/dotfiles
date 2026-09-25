import QtQuick
import Quickshell.Io

Item {
  id: root
  required property var shell
  property Item anchorItem: null
  property string popupName: "monitor"
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: shell && shell.popupName === popupName
  function showPopup() { if (root.shell) root.shell.togglePopup(root.popupName) }
  function hidePopup() { if (root.shell && root.opened) root.shell.closePopup() }
  function open() { root.showPopup() }
  function close() { root.hidePopup() }
  function closeForPopoutSwitch() { close() }
  function toggle() { opened ? close() : open() }
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  IpcHandler {
    enabled: root.manageIpc && root.ipcTarget !== ""
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }
}

import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root
  required property var shell
  property Item anchorItem: null
  property QtObject bar: null
  property string moduleName: ""
  property string popupName: "monitor"
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: shell && shell.popupName === popupName
  readonly property color barForeground: bar ? bar.foreground : Color.foreground
  property QtObject controller: QtObject {
    function show() { if (root.shell) root.shell.togglePopup(root.popupName) }
    function hide() { if (root.shell && root.opened) root.shell.closePopup() }
  }
  function open() { controller.show() }
  function close() { controller.hide() }
  function closeForPopoutSwitch() { close() }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) { return false }
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

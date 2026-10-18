import QtQuick

Item {
  id: root
  required property var window
  readonly property var screen: window ? window.screen : null
  readonly property bool windowMapped: window && window.backingWindowVisible
  property bool remapping: false
  visible: false

  function remap() {
    if (windowMapped) remapping = true
  }
  function finishRemap() { remapping = false }

  Connections {
    target: root.screen
    function onXChanged() { root.remap() }
    function onYChanged() { root.remap() }
  }
  onWindowMappedChanged: {
    if (remapping && !windowMapped) Qt.callLater(root.finishRemap)
  }
}

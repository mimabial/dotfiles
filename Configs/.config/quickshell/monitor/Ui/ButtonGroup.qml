pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Row {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family
  property real fontSize: Commons.Style.font.body
  property bool focusable: true

  property int cursorIndex: -1

  property int focusedOptionIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  spacing: Commons.Style.spacing.md

  activeFocusOnTab: focusable

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object" && o.label !== undefined) ? String(o.label) : String(o)
  }
  function optionIcon(o) {
    return (o && typeof o === "object" && o.icon) ? String(o.icon) : ""
  }
  function optionTooltip(o) {
    return (o && typeof o === "object" && o.tooltip) ? String(o.tooltip) : ""
  }

  function selectedOptionIndex() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return i
    return -1
  }

  function activateFocused() {
    if (focusedOptionIndex < 0 || focusedOptionIndex >= options.length) return
    root.changed(optionValue(options[focusedOptionIndex]))
  }

  onActiveFocusChanged: {
    if (activeFocus) {
      var idx = selectedOptionIndex()
      focusedOptionIndex = idx < 0 ? 0 : idx
    } else {
      focusedOptionIndex = -1
    }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H
        || event.text === "h") {
      focusedOptionIndex = Math.max(0, (focusedOptionIndex < 0 ? 0 : focusedOptionIndex) - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L
        || event.text === "l") {
      var max = options.length - 1
      var next = (focusedOptionIndex < 0 ? 0 : focusedOptionIndex) + 1
      focusedOptionIndex = Math.min(max, next)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      activateFocused()
      event.accepted = true
    }
  }

  Repeater {
    model: root.options

    delegate: Button {
      required property var modelData
      required property int index
      text: root.optionLabel(modelData)
      iconText: root.optionIcon(modelData)
      tooltipText: root.optionTooltip(modelData)
      selected: root.optionValue(modelData) === root.value
      hasCursor: root.cursorIndex === index
        || (root.activeFocus && root.focusedOptionIndex === index)
      bordered: true
      foreground: root.foreground
      background: root.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      onClicked: root.changed(root.optionValue(modelData))
      onHovered: function(h) { root.hovered(index, h) }
    }
  }
}

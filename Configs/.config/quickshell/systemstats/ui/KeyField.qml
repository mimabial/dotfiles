pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string text: ""
  property string placeholderText: ""
  property int maximumLength: 32767
  property int horizontalAlignment: Text.AlignLeft
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property real horizontalPadding: Commons.Style.spacing.controlPaddingX
  property real verticalPadding: Commons.Style.spacing.inputPaddingY
  property alias font: label.font
  readonly property int caretBlinkMs: Qt.styleHints.cursorFlashTime / 2

  signal accepted()
  signal editingFinished()

  readonly property bool hot: mouse.containsMouse
  readonly property var borderSpec: Commons.Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  function typed(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return ""
    var value = String(event.text || "")
    for (var i = 0; i < value.length; i++) if (value.charCodeAt(i) < 32 || value.charCodeAt(i) === 127) return ""
    return value
  }

  activeFocusOnTab: true
  implicitWidth: Commons.Style.space(160)
  implicitHeight: label.implicitHeight + 2 * verticalPadding + Commons.Border.top(borderSpec) + Commons.Border.bottom(borderSpec)

  onActiveFocusChanged: if (!activeFocus) editingFinished()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Backspace) {
      root.text = event.modifiers & Qt.ControlModifier ? "" : root.text.slice(0, -1)
      event.accepted = true
    } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
      root.text = ""
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.accepted()
      root.editingFinished()
      event.accepted = true
    } else {
      var value = root.typed(event)
      if (value === "") return
      if (root.text.length < root.maximumLength) root.text = (root.text + value).slice(0, root.maximumLength)
      event.accepted = true
    }
  }

  BorderSurface {
    anchors.fill: parent
    color: Commons.Style.controlFill(root.activeFocus, root.hot, root.foreground, root.accent)
    borderSpec: root.borderSpec
    radius: Commons.Style.cornerRadius
  }

  Item {
    id: inner
    anchors.fill: parent
    anchors.leftMargin: root.horizontalPadding + Commons.Border.left(root.borderSpec)
    anchors.rightMargin: root.horizontalPadding + Commons.Border.right(root.borderSpec)
    clip: true

    Text {
      id: label
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      x: implicitWidth > inner.width ? inner.width - implicitWidth - caret.width
        : (root.horizontalAlignment === Text.AlignRight ? inner.width - implicitWidth - caret.width
          : (root.horizontalAlignment === Text.AlignHCenter ? (inner.width - implicitWidth) / 2 : 0))
      text: root.text !== "" ? root.text : root.placeholderText
      color: root.text !== "" ? root.foreground : Commons.Util.scaleAlpha(root.foreground, Commons.Style.mutedTextAlpha)
      font.family: Commons.Style.font.menuFamily
      font.pixelSize: Commons.Style.font.body
    }

    Rectangle {
      id: caret
      visible: root.activeFocus && blink.on
      x: root.text !== "" ? label.x + label.implicitWidth : label.x
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(1, Commons.Style.spaceReal(1))
      height: label.font.pixelSize * 1.2
      color: root.foreground
    }
  }

  Timer {
    id: blink
    property bool on: true
    interval: root.caretBlinkMs
    repeat: true
    running: root.activeFocus
    onRunningChanged: on = true
    onTriggered: on = !on
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.IBeamCursor
    onClicked: root.forceActiveFocus()
  }
}

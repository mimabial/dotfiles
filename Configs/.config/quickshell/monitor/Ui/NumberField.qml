import QtQuick
import QtQuick.Controls as QQC
import qs.Commons as Commons

Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family
  property real fontSize: Commons.Style.font.body
  property real fieldWidth: Commons.Style.spacing.numberFieldWidth
  property bool hasCursor: false
  property bool pointerHovered: false
  property alias field: spin

  signal modified(int value)
  signal hovered(bool on)

  spacing: Commons.Style.spacing.md

  TextMetrics {
    id: stepperGlyph
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    text: "󰅀"
  }

  Text {
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.bodySmall
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    implicitHeight: Math.max(Commons.Style.spacing.controlHeight, root.fontSize + Commons.Style.spacing.controlPaddingY * 2)
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    hoverEnabled: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    readonly property bool inputFocused: spin.activeFocus
    readonly property bool inputHighlighted: root.pointerHovered || root.hasCursor
    readonly property var normalBorderSpec: Commons.Border.controlSpec("normal", root.foreground, root.accent)
    readonly property real borderTop: Commons.Border.top(normalBorderSpec)
    readonly property real borderRight: Commons.Border.right(normalBorderSpec)
    readonly property real borderBottom: Commons.Border.bottom(normalBorderSpec)
    readonly property real stepperWidth: stepperGlyph.advanceWidth + Commons.Style.spacing.controlGap * 2
    readonly property real stepperHeight: (height - borderTop - borderBottom) / 2

    function stepperFill(button) {
      return button.pressed ? Commons.Style.pressedFillFor(root.foreground, root.accent)
        : button.hovered ? Commons.Style.hoverFillFor(root.foreground, root.accent)
        : "transparent"
    }

    leftPadding: Commons.Border.left(normalBorderSpec) + Commons.Style.spacing.controlPaddingX
    rightPadding: borderRight + Commons.Style.spacing.controlPaddingX + stepperWidth
    topPadding: borderTop
    bottomPadding: borderBottom

    onValueModified: root.modified(value)

    up.indicator: Rectangle {
      x: spin.width - width - spin.borderRight
      y: spin.borderTop
      width: spin.stepperWidth
      height: spin.stepperHeight
      radius: Math.min(Commons.Style.cornerRadius, height / 2)
      color: spin.stepperFill(spin.up)
      Behavior on color { ColorAnimation { duration: 100 } }

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "󰅃"
        color: Qt.darker(root.foreground, 1.2)
        font: stepperGlyph.font
      }
    }

    down.indicator: Rectangle {
      x: spin.width - width - spin.borderRight
      y: spin.borderTop + spin.stepperHeight
      width: spin.stepperWidth
      height: spin.stepperHeight
      radius: Math.min(Commons.Style.cornerRadius, height / 2)
      color: spin.stepperFill(spin.down)
      Behavior on color { ColorAnimation { duration: 100 } }

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font: stepperGlyph.font
      }
    }

    background: BorderSurface {
      color: Commons.Style.controlFill(spin.inputFocused, spin.inputHighlighted, root.foreground, root.accent)
      borderSpec: spin.normalBorderSpec
      radius: Commons.Style.cornerRadius

      HoverHandler {
        onHoveredChanged: {
          root.pointerHovered = hovered
          root.hovered(hovered)
        }
      }
    }

    contentItem: TextInput {
      id: numberInput
      text: spin.displayText
      clip: true
      font: spin.font
      color: root.foreground
      selectionColor: Commons.Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      horizontalAlignment: Qt.AlignHCenter
      verticalAlignment: Qt.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      onActiveFocusChanged: if (activeFocus && !readOnly) Qt.callLater(function() {
        if (numberInput.activeFocus) numberInput.selectAll()
      })
    }
  }
}

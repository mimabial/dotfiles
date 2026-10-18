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
    readonly property var stateBorderSpec: Commons.Border.controlSpec(inputFocused ? "focus" : (inputHighlighted ? "hover-cursor" : "normal"), root.foreground, root.accent)

    leftPadding: Commons.Border.left(stateBorderSpec) + Commons.Style.spacing.controlPaddingX
    rightPadding: Commons.Border.right(stateBorderSpec) + Commons.Style.spacing.controlPaddingX
      + (up.indicator ? up.indicator.width : 0)
    topPadding: Commons.Border.top(stateBorderSpec)
    bottomPadding: Commons.Border.bottom(stateBorderSpec)

    onValueModified: root.modified(value)

    background: BorderSurface {
      id: fieldBackground
      color: Commons.Style.controlFill(spin.inputFocused, spin.inputHighlighted, root.foreground, root.accent)
      borderSpec: spin.stateBorderSpec
      radius: Commons.Style.cornerRadius

      HoverHandler {
        onHoveredChanged: {
          root.pointerHovered = hovered
          root.hovered(hovered)
        }
      }

      Item {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: fieldBackground.borderTop
        anchors.rightMargin: fieldBackground.borderRight
        anchors.bottomMargin: fieldBackground.borderBottom
        width: Math.max(spin.up.indicator ? spin.up.indicator.width : 0,
                        spin.down.indicator ? spin.down.indicator.width : 0)

        Rectangle {
          width: parent.width
          height: parent.height / 2
          radius: Math.min(Commons.Style.cornerRadius, height / 2)
          color: spin.up.pressed
            ? Commons.Style.pressedFillFor(root.foreground, root.accent)
            : spin.up.hovered
              ? Commons.Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"
          Behavior on color { ColorAnimation { duration: 100 } }
        }

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height / 2
          radius: Math.min(Commons.Style.cornerRadius, height / 2)
          color: spin.down.pressed
            ? Commons.Style.pressedFillFor(root.foreground, root.accent)
            : spin.down.hovered
              ? Commons.Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"
          Behavior on color { ColorAnimation { duration: 100 } }
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

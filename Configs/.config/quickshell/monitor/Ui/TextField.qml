import QtQuick
import QtQuick.Controls
import qs.Commons as Commons

TextField {
  id: root

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Commons.Style.selectionFillFor(foreground, accent)
  property bool password: false
  property real horizontalPadding: Commons.Style.spacing.controlPaddingX
  property real verticalPadding: Commons.Style.spacing.inputPaddingY

  property bool hasCursor: false

  readonly property bool inputFocused: activeFocus
  readonly property bool inputHighlighted: hovered || hasCursor
  readonly property var stateBorderSpec: Commons.Border.controlSpec(inputFocused ? "focus" : (inputHighlighted ? "hover-cursor" : "normal"), root.foreground, root.accent)

  echoMode: password ? TextInput.Password : TextInput.Normal
  font.family: Commons.Style.font.family
  font.pixelSize: Commons.Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding + Commons.Border.left(stateBorderSpec)
  rightPadding: horizontalPadding + Commons.Border.right(stateBorderSpec)
  topPadding: verticalPadding + Commons.Border.top(stateBorderSpec)
  bottomPadding: verticalPadding + Commons.Border.bottom(stateBorderSpec)

  background: BorderSurface {
    color: Commons.Style.controlFill(root.inputFocused, root.inputHighlighted, root.foreground, root.accent)
    borderSpec: root.stateBorderSpec
    radius: Commons.Style.cornerRadius
  }
}

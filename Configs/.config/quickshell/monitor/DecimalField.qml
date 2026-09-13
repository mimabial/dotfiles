pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import "Ui"

Column {
  id: decimalField
  required property var controller
  required property Item keyTarget
  property string label: ""
  property real value: 0
  property int decimals: 2
  property bool hasCursor: false
  property alias input: decimalInput
  signal modified(real value)

  spacing: Style.space(4)

  function formatted() {
    var number = Number(decimalField.value || 0)
    return isFinite(number) ? number.toFixed(decimalField.decimals) : Number(0).toFixed(decimalField.decimals)
  }

  onValueChanged: {
    if (!decimalInput.activeFocus) decimalInput.text = decimalField.formatted()
  }

  PanelSectionHeader {
    text: decimalField.label
    foreground: decimalField.controller.foreground
    fontFamily: decimalField.controller.fontFamily
  }

  TextField {
    id: decimalInput
    width: parent.width
    text: decimalField.formatted()
    enabled: decimalField.enabled
    hasCursor: decimalField.hasCursor
    foreground: decimalField.controller.foreground
    validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
    onEditingFinished: {
      var returnToKeyboard = activeFocus
      var parsed = Number(text)
      if (isFinite(parsed)) decimalField.modified(parsed)
      else text = decimalField.formatted()
      if (returnToKeyboard)
        Qt.callLater(function() { decimalField.keyTarget.forceActiveFocus() })
    }
  }
}

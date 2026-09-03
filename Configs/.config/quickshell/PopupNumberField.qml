pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Column {
    id: root
    required property var shell
    property string label: ""
    property int value: 0
    property int minimum: 0
    property int maximum: 999
    property bool keyboardEnabled: true
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    property bool canceling: false
    signal committed(int value)
    signal accepted
    signal clicked(int button)
    spacing: Style.xs
    opacity: enabled ? 1 : .45
    onValueChanged: if (!field.activeFocus) field.text = String(value)
    onClicked: beginEditing()

    function commit() {
        const next = Math.max(minimum, Math.min(maximum, Number(field.text) || minimum))
        field.text = String(next)
        committed(next)
    }
    function beginEditing() { field.forceActiveFocus(); field.selectAll() }
    function finishEditing(step) {
        field.focus = false
        Qt.callLater(() => {
            if (!shell.popupCard) return
            shell.popupCard.resumeKeyboard()
            if (step) shell.popupCard.moveCursor(step)
        })
    }
    function adjustKeyboard(direction) {
        const next = Math.max(minimum, Math.min(maximum, value + direction))
        field.text = String(next)
        committed(next)
    }

    Text {
        width: parent.width; text: root.label.toUpperCase()
        color: root.shell.alpha(root.shell.foreground, .45)
        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        font.bold: true; horizontalAlignment: Text.AlignHCenter
    }
    TextField {
        id: field
        width: parent.width; height: Style.controlHeight + Style.sm
        text: String(root.value); enabled: root.enabled
        color: root.shell.foreground; horizontalAlignment: TextInput.AlignHCenter
        font.family: root.shell.fontFamily; font.pixelSize: Style.title; font.bold: true
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: root.minimum; top: root.maximum }
        onActiveFocusChanged: {
            if (!root.shell.popupCard) return
            root.shell.popupCard.wantsKeyboard = activeFocus
            if (activeFocus) { root.shell.popupCard.selectRow(root); selectAll() }
        }
        onEditingFinished: {
            if (!root.canceling) root.commit()
            root.canceling = false
        }
        onAccepted: {
            root.finishEditing(0)
            root.accepted()
        }
        Keys.onEscapePressed: {
            root.canceling = true
            text = String(root.value)
            root.finishEditing(0)
        }
        Keys.onTabPressed: root.finishEditing(1)
        Keys.onBacktabPressed: root.finishEditing(-1)
        Keys.onUpPressed: root.adjustKeyboard(1)
        Keys.onDownPressed: root.adjustKeyboard(-1)
        Keys.onPressed: event => {
            if ([Qt.Key_J, Qt.Key_K, Qt.Key_H, Qt.Key_L].includes(event.key))
                event.accepted = true
        }
        background: Rectangle {
            radius: root.shell.rounding
            color: root.cursored ? root.shell.hoverFill() : root.shell.alpha(root.shell.foreground, .06)
            border.width: root.cursored || parent.activeFocus ? 2 : 1
            border.color: root.cursored ? root.shell.hoverEdge(.85)
                : root.shell.alpha(root.shell.foreground, parent.activeFocus ? .45 : .18)
        }
    }
}

import QtQuick
import QtQuick.Controls

// The text input every popup form uses. An inputMask field is the reason this
// is shared: an untouched mask still carries its separators, so the cursor has
// to be pinned to the start or the first keystroke lands mid-pattern.
TextField {
    id: root
    required property var shell
    signal submitted()

    height: Style.px(24)
    leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
    topPadding: 0; bottomPadding: 0
    color: root.shell.foreground
    placeholderTextColor: root.shell.alpha(root.shell.foreground, .28)
    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall

    readonly property bool masked: inputMask !== ""
    readonly property bool blank: !/\d/.test(text)
    onActiveFocusChanged: if (activeFocus && masked && blank) cursorPosition = 0
    onCursorPositionChanged: if (masked && blank && cursorPosition !== 0) cursorPosition = 0

    // "" until the user has actually typed a digit
    readonly property string value: {
        const packed = String(text).replace(/\s/g, "")
        return /\d/.test(packed) ? packed : ""
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            && (event.modifiers & Qt.ControlModifier)) {
            root.submitted()
            event.accepted = true
        }
    }

    background: Rectangle {
        radius: root.shell.rounding
        color: root.shell.alpha(root.shell.foreground, .06)
        border.width: 1
        border.color: root.shell.alpha(root.shell.foreground, root.activeFocus ? .45 : .18)
    }
}

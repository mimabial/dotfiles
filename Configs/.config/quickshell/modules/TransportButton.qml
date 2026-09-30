import QtQuick
import qs.Ui as Ui
import ".."

Ui.Button {
    required property var shell
    readonly property real inactiveOpacity: .35
    fontFamily: shell.iconGlyphFont; fontSize: Style.title; foreground: shell.foreground
    opacity: enabled ? 1 : inactiveOpacity
}

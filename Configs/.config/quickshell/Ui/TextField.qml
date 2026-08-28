import QtQuick
import QtQuick.Controls
import "../Commons" as Commons

TextField {
    id: root

    property color foreground: Commons.Color.foreground
    property color accent: Commons.Color.accent

    font.family: Commons.Style.font.menuFamily
    font.pixelSize: Commons.Style.font.body
    color: foreground
    selectionColor: Commons.Util.alpha(accent, 0.45)
    selectedTextColor: foreground
    placeholderTextColor: Commons.Util.alpha(foreground, 0.52)
    leftPadding: Commons.Style.space(10)
    rightPadding: Commons.Style.space(10)
    topPadding: Commons.Style.space(7)
    bottomPadding: Commons.Style.space(7)

    background: Rectangle {
        color: root.activeFocus || root.hovered ? Commons.Util.alpha(root.accent, 0.10) : "transparent"
        border.color: root.activeFocus ? root.accent : Commons.Util.alpha(root.foreground, 0.38)
        border.width: Commons.Style.normalBorderWidth
        radius: Commons.Style.cornerRadius
    }
}

import QtQuick
import QtQuick.Controls
import "Ui" as Ui

// AlwaysOn while the list overflows: an AsNeeded bar fades out whenever the
// pointer is elsewhere, which is exactly when the list has to say it continues.
Ui.PanelScrollBar {
    id: root
    required property var shell
    policy: size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    padding: 0
    implicitWidth: Style.px(Style.popupStyle.scrollbarWidth)
    implicitHeight: implicitWidth
    hoverEnabled: true
    contentItem: Rectangle {
        radius: Math.min(width / 2, root.shell.rounding)
        color: root.shell.foreground
    }
}

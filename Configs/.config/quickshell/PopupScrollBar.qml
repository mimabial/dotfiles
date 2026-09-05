import QtQuick
import QtQuick.Controls

// AlwaysOn while the list overflows: an AsNeeded bar fades out whenever the
// pointer is elsewhere, which is exactly when the list has to say it continues.
ScrollBar {
    id: root
    required property var shell
    policy: size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    padding: 0
    width: Style.sm
    contentItem: Rectangle {
        radius: width / 2
        color: root.shell.alpha(root.shell.foreground, root.pressed ? .55 : .3)
    }
}

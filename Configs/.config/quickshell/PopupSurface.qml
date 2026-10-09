pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Rectangle {
    id: root
    required property var shell
    property color background: root.shell.role("bg", "#0c1021")
    property color borderColor: root.shell.role("alt_br", root.shell.foreground)
    property real surfaceOpacity: root.shell.style.box("popup").surfaceOpacity ?? Commons.Style.popupSurfaceOpacity
    property real borderOpacity: root.shell.style.box("popup").borderOpacity ?? Commons.Style.popupBorderOpacity

    color: root.shell.alpha(root.background, root.surfaceOpacity)
    border.color: root.shell.alpha(root.borderColor, root.borderOpacity)
    border.width: root.shell.borderWidth
    radius: root.shell.rounding
}

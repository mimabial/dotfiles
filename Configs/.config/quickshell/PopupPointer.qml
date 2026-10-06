pragma ComponentBehavior: Bound
import QtQuick

HoverHandler {
    id: root
    required property var shell
    required property var row
    enabled: root.row.navigable && root.row.enabled
    function follow() {
        if (root.hovered && root.shell.popupCard) root.shell.popupCard.followPointer(root.row, root.point.position.x, root.point.position.y)
    }
    onPointChanged: follow()
    onHoveredChanged: follow()
}

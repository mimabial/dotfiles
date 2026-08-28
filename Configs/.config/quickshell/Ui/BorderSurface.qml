import QtQuick
import "../Commons" as Commons

Rectangle {
    id: root

    property var borderSpec: Commons.Border.none()
    property real padding: 0
    property real topPadding: padding
    property real rightPadding: padding
    property real bottomPadding: padding
    property real leftPadding: padding

    readonly property real borderTop: Commons.Border.top(borderSpec)
    readonly property real borderRight: Commons.Border.right(borderSpec)
    readonly property real borderBottom: Commons.Border.bottom(borderSpec)
    readonly property real borderLeft: Commons.Border.left(borderSpec)
    readonly property real contentTopInset: borderTop + topPadding
    readonly property real contentRightInset: borderRight + rightPadding
    readonly property real contentBottomInset: borderBottom + bottomPadding
    readonly property real contentLeftInset: borderLeft + leftPadding

    border.color: Commons.Border.color(borderSpec)
    border.width: Commons.Border.uniformWidth(borderSpec)
}

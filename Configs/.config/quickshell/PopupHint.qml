pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Text {
    id: root
    required property var shell
    property bool error: false
    readonly property color errorColor: root.shell.role("error", root.shell.foreground)
    visible: root.text !== ""
    width: root.error && parent ? parent.width : implicitWidth
    textFormat: root.error ? Text.PlainText : Text.AutoText
    wrapMode: root.error ? Text.Wrap : Text.NoWrap
    horizontalAlignment: root.error ? Text.AlignLeft : Text.AlignHCenter
    color: root.error ? root.shell.foreground : root.shell.mutedText
    font.family: root.shell.fontFamily
    font.pixelSize: root.error ? Commons.Style.font.bodySmall : Commons.Style.font.caption
    leftPadding: root.error ? Commons.Style.spacing.controlPaddingX + errorIcon.width + Commons.Style.spacing.lg : 0
    rightPadding: root.error ? Commons.Style.spacing.controlPaddingX : 0
    topPadding: root.error ? Commons.Style.spacing.controlPaddingY : 0
    bottomPadding: root.topPadding

    Rectangle {
        anchors.fill: parent
        z: -1
        visible: root.error
        radius: root.shell.rounding
        color: root.shell.alpha(root.errorColor, Commons.Style.normalFillAlpha)
        border.width: Commons.Style.normalBorderWidth
        border.color: root.shell.alpha(root.errorColor, Commons.Style.selectedFillAlpha)
    }
    Text {
        id: errorIcon
        visible: root.error
        x: Commons.Style.spacing.controlPaddingX
        y: root.topPadding
        text: "\u{f0028}"
        color: root.errorColor
        font.family: root.font.family
        font.pixelSize: root.font.pixelSize
    }
}

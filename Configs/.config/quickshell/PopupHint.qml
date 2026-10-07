pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

Text {
    id: root
    required property var shell
    visible: root.text !== ""
    wrapMode: Text.NoWrap
    horizontalAlignment: Text.AlignHCenter
    color: root.shell.mutedText
    font.family: root.shell.fontFamily
    font.pixelSize: Commons.Style.font.caption
}

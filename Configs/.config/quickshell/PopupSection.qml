import QtQuick

Text {
    id: root
    required property var shell
    property string value: ""
    width: value !== "" && parent ? parent.width : undefined
    color: shell.mutedText
    font.family: shell.fontFamily
    font.pixelSize: Style.caption
    font.bold: true
    topPadding: Math.ceil(font.pixelSize * Style.glyphOvershoot)

    Text {
        visible: root.value !== ""
        anchors.right: parent.right; anchors.rightMargin: Style.md; anchors.baseline: parent.baseline
        text: root.value; color: root.color
        font.family: root.font.family; font.pixelSize: root.font.pixelSize; font.bold: true
    }
}

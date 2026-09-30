import QtQuick

// Section label inside a popup ("AUDIO", "OUTPUT DEVICE"). The top pad keeps
// nerd-font ascenders from being clipped by a surrounding ListView.
Text {
    id: root
    required property var shell
    // set to put a reading on the right of the header row, so the control below
    // needs no label of its own
    property string value: ""
    width: value !== "" && parent ? parent.width : undefined
    color: Qt.darker(shell.foreground, 1.4)
    font.family: shell.fontFamily
    font.pixelSize: Style.caption
    font.bold: true
    topPadding: Math.ceil(font.pixelSize * 0.15)

    Text {
        visible: root.value !== ""
        anchors.right: parent.right; anchors.rightMargin: Style.md; anchors.baseline: parent.baseline
        text: root.value; color: root.color
        font.family: root.font.family; font.pixelSize: root.font.pixelSize; font.bold: true
    }
}

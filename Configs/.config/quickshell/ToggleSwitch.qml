import QtQuick

Rectangle {
    required property var shell
    property bool checked: false
    signal toggled
    readonly property int trackHeight: Math.round(Style.caption * 1.5)
    width: Math.round(trackHeight * 1.9); height: trackHeight; radius: shell.rounding
    color: checked ? shell.alpha(shell.role("act_bg", shell.accent), .55)
        : shell.alpha(shell.foreground, .12)
    border.color: shell.alpha(shell.foreground, mouse.containsMouse ? .45 : .22)
    Behavior on color { ColorAnimation { duration: Style.hoverDuration } }
    Rectangle {
        readonly property int pad: 2
        width: parent.height - pad * 2; height: width
        radius: Math.max(1, shell.rounding - 1)
        y: pad
        x: parent.checked ? parent.width - width - pad : pad
        color: parent.checked ? shell.role("act_fg", shell.foreground)
            : shell.alpha(shell.foreground, .6)
        Behavior on x { NumberAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled()
    }
}

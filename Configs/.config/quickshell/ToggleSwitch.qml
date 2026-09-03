import QtQuick

Rectangle {
    id: root
    required property var shell
    property bool checked: false
    property bool keyboardEnabled: false
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    signal toggled
    signal clicked(int button)
    onClicked: toggled()
    function adjustKeyboard(direction) {
        if ((direction > 0) !== checked) toggled()
    }
    readonly property int trackHeight: Math.round(Style.caption * 1.5)
    width: Math.round(trackHeight * 1.9); height: trackHeight; radius: shell.rounding
    color: checked ? shell.alpha(shell.role("act_bg", shell.accent), .55)
        : shell.alpha(shell.foreground, .12)
    border.color: cursored ? shell.hoverEdge(.85)
        : shell.alpha(shell.foreground, mouse.containsMouse ? .45 : .22)
    border.width: cursored ? 2 : 1
    Behavior on color { ColorAnimation { duration: Style.hoverDuration } }
    Rectangle {
        readonly property int pad: 2
        width: parent.height - pad * 2; height: width
        radius: Math.max(1, root.shell.rounding - 1)
        y: pad
        x: parent.checked ? parent.width - width - pad : pad
        color: parent.checked ? root.shell.role("act_fg", root.shell.foreground)
            : root.shell.alpha(root.shell.foreground, .6)
        Behavior on x { NumberAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor; onClicked: root.clicked(Qt.LeftButton)
    }
}

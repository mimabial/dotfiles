import QtQuick

Item {
    id: root
    required property var shell
    property string label: ""
    property string value: ""
    property bool interactive: false
    readonly property bool navigable: interactive && enabled
    property bool cursored: false
    signal clicked(int button)
    function activateKeyboard() { clicked(Qt.LeftButton) }
    width: parent ? parent.width : implicitWidth
    implicitWidth: pairLabel.implicitWidth + Style.lg + pairValue.implicitWidth
    implicitHeight: pairValue.implicitHeight

    Text { id: pairLabel; width: Math.max(0, parent.width - pairValue.width - Style.lg); text: root.label; elide: Text.ElideRight; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    Text {
        id: pairValue
        anchors.right: parent.right; width: Math.min(implicitWidth, parent.width)
        text: root.value || "—"; elide: Text.ElideRight
        color: root.cursored || (!root.shell.popupCard?.open && mouse.containsMouse) ? root.shell.accent : root.shell.foreground
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
    }
    MouseArea { id: mouse; anchors.fill: parent; enabled: root.interactive; hoverEnabled: enabled; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked(Qt.LeftButton) }
    PopupPointer { shell: root.shell; row: root }
}

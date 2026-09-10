pragma ComponentBehavior: Bound

import QtQuick

Text {
    id: root
    required property var popup
    required property string glyph
    property real size: Style.display
    text: glyph
    color: root.popup.shell.alpha(root.popup.shell.foreground, mouse.containsMouse ? 1 : .75)
    font.family: root.popup.shell.fontFamily; font.pixelSize: size
    signal activated
    MouseArea { id: mouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: parent.activated() }
}

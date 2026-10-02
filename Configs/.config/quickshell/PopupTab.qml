pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: root
    required property var shell
    property string text: ""
    property string icon: ""
    property bool selected: false
    property bool keyboardEnabled: true
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    signal clicked(int button)
    implicitWidth: label.implicitWidth + (glyph.visible ? glyph.implicitWidth + content.spacing : 0) + Style.controlPaddingX * 2
    implicitHeight: Style.controlHeight
    radius: shell.rounding
    color: selected ? shell.selectedFill() : mouse.containsMouse || cursored ? shell.hoverFill() : "transparent"
    border.color: cursored ? shell.hoverEdge(.85) : selected ? shell.selectedEdge() : "transparent"
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent; spacing: Style.sm
        Text { id: glyph; visible: root.icon !== ""; anchors.verticalCenter: parent.verticalCenter; text: root.icon; color: label.color; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.bodySmall }
        Text {
            id: label
            width: Math.min(implicitWidth, root.width - Style.controlPaddingX * 2 - (glyph.visible ? glyph.implicitWidth + content.spacing : 0))
            anchors.verticalCenter: parent.verticalCenter
            text: root.text.toUpperCase(); elide: Text.ElideRight
            color: root.selected ? root.shell.foreground : root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: root.selected; font.letterSpacing: 1
        }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked(Qt.LeftButton) }
}

import QtQuick

Rectangle {
    id: root
    required property var shell
    property string glyph: ""
    property string hint: ""
    property color glyphColor: shell.foreground
    property bool keyboardEnabled: true
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    signal clicked(int button)
    implicitWidth: Style.controlHeight; implicitHeight: Style.controlHeight
    radius: shell.rounding
    color: mouse.containsMouse || cursored ? shell.hoverFill(3) : "transparent"

    Text { anchors.centerIn: parent; text: root.glyph; color: root.glyphColor; font.family: root.shell.fontFamily; font.pixelSize: Style.title }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked(Qt.LeftButton) }
    BarTooltip { shell: root.shell; anchorItem: root; text: root.hint; hovered: mouse.containsMouse }
}

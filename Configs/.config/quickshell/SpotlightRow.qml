pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

Item {
    id: root
    required property var shell
    property string section: ""
    property string icon: ""
    property string iconSource: ""
    property string title: ""
    property string detail: ""
    property string kind: ""
    property bool cursored: false
    property bool checked: false
    readonly property int iconSize: Style.px(20)
    signal clicked(int button)
    signal pointerMoved(point position)
    implicitHeight: (section !== "" ? Style.spotlightSectionHeight : 0) + Style.popupRowHeight

    Text {
        visible: root.section !== ""
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Style.xl + Style.controlPaddingX; anchors.rightMargin: anchors.leftMargin
        anchors.bottom: surface.top; anchors.bottomMargin: Style.xs
        text: root.section; elide: Text.ElideRight
        color: root.shell.mutedText
        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
    }
    Rectangle {
        id: surface
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: Style.xl; anchors.rightMargin: Style.xl
        height: Style.popupRowHeight
        radius: root.shell.rounding
        color: root.cursored ? root.shell.hoverFill() : "transparent"
        border.color: root.cursored ? root.shell.hoverEdge(.85) : "transparent"

        IconImage {
            id: iconImage
            visible: root.iconSource !== ""
            x: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.iconSize; implicitHeight: root.iconSize
            source: root.iconSource
        }
        Text {
            visible: !iconImage.visible
            x: Style.controlPaddingX; width: root.iconSize; anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.icon
            color: root.cursored ? root.shell.foreground : root.shell.alpha(root.shell.foreground, .75)
            font.family: root.shell.fontFamily; font.pixelSize: Style.title + 3
        }
        Text {
            id: kindText
            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: root.checked ? "✓" : root.kind
            color: root.checked ? root.shell.accent : root.shell.faintText
            font.family: root.shell.fontFamily; font.pixelSize: Style.body
        }
        Row {
            anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX + root.iconSize + Style.xl
            anchors.right: kindText.left; anchors.rightMargin: Style.xxxl
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.xl
            Text {
                id: titleText
                width: Math.min(implicitWidth, parent.width)
                anchors.verticalCenter: parent.verticalCenter
                text: root.title; elide: Text.ElideRight
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.title
                font.weight: root.cursored ? Font.Medium : Font.Normal
            }
            Text {
                visible: text !== ""
                width: Math.max(0, parent.width - titleText.width - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: root.detail; elide: Text.ElideRight
                color: root.shell.faintText
                font.family: root.shell.fontFamily; font.pixelSize: Style.body
            }
        }
        MouseArea {
            id: pointerArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: mouse => root.pointerMoved(pointerArea.mapToGlobal(mouse.x, mouse.y))
            onClicked: mouse => root.clicked(mouse.button)
        }
    }
}

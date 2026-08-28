import QtQuick
import "../Commons" as Commons

BorderSurface {
    id: root

    property string iconText: ""
    property string tooltipText: ""
    property color foreground: Commons.Color.foreground
    property color hoverColor: foreground
    property string fontFamily: Commons.Style.font.family
    property real fontSize: Commons.Style.font.caption
    property real size: Math.max(Commons.Style.space(22), fontSize + Commons.Style.space(8))
    property bool focusable: false
    property bool hasCursor: false
    property bool bordered: false
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    activeFocusOnTab: focusable
    radius: Commons.Style.cornerRadius
    color: hot ? Commons.Util.alpha(hoverColor, 0.14) : "transparent"
    borderSpec: bordered && hot
        ? Commons.Border.flat(Commons.Util.alpha(hoverColor, 0.55), 1)
        : Commons.Border.none()
    readonly property bool hot: enabled && (mouse.containsMouse || hasCursor || activeFocus)

    Keys.onReturnPressed: if (focusable) root.clicked()
    Keys.onEnterPressed: if (focusable) root.clicked()
    Keys.onSpacePressed: if (focusable) root.clicked()

    Text {
        anchors.centerIn: parent
        text: root.iconText
        color: root.enabled ? (root.hot ? root.hoverColor : root.foreground)
                            : Commons.Util.alpha(root.foreground, 0.35)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.focusable) root.forceActiveFocus()
            root.clicked()
        }
    }
}

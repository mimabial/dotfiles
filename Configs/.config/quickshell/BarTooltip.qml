import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property Item anchorItem
    required property var shell
    property string text: ""
    property bool hovered: false
    property int textFormat: Text.PlainText
    property bool ready: false
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property string edge: shell.barEdge

    property bool dismissed: false

    function dismiss() { dismissed = true; update() }
    function update() { ready = false; if (hovered && text && !dismissed) hoverDwellTimer.restart(); else hoverDwellTimer.stop() }
    onHoveredChanged: { if (!hovered) dismissed = false; update() }
    onTextChanged: update()
    visible: ready && hovered && text !== ""
    color: "transparent"
    implicitWidth: label.width + 16
    implicitHeight: label.implicitHeight + 10

    Timer { id: hoverDwellTimer; interval: Style.tooltipDelay; onTriggered: root.ready = true }
    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1; rect.height: 1
        onAnchoring: {
            let x = root.anchorItem.width / 2 - root.width / 2
            let y = root.anchorItem.height + 6
            if (root.edge === "bottom") y = -root.height - 6
            else if (root.edge === "left") { x = root.anchorItem.width + 6; y = root.anchorItem.height / 2 - root.height / 2 }
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, y)
            anchor.rect.x = Math.round(point.x); anchor.rect.y = Math.round(point.y)
        }
    }
    Rectangle {
        anchors.fill: parent; radius: root.shell.rounding
        color: root.shell.alpha(Style.popupTinted(root.shell.background), Style.popupSurfaceOpacity)
        border.color: root.shell.alpha(Style.popupBorder(root.shell.role("br", root.shell.foreground)), .45)
        Text {
            id: label; anchors.centerIn: parent; width: Math.min(340, implicitWidth)
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            text: root.text; textFormat: root.textFormat; wrapMode: Text.Wrap
        }
    }
}

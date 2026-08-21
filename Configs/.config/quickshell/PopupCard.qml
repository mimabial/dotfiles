import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: root
    required property Item anchorItem
    required property var shell
    required property string popupName
    property bool popupEnabled: true
    property int contentWidth: 380
    property int contentHeight: holder.childrenRect.height + padding * 2
    property int margin: Style.popupGap
    property int padding: Style.popupPadding
    property color background: shell.role("bg", "#0c1021")
    property real surfaceOpacity: 0.94
    // windows that belong to this panel and must not dismiss it (submenu flyouts)
    property var extraGrabWindows: []
    readonly property bool open: popupEnabled && shell.popupName === popupName
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property var returnFocus: null
    readonly property string position: shell.layoutName === "main" ? "right" : ["left", "sidebar"].includes(shell.layoutName) ? "left" : shell.layoutName === "top" ? "top" : "bottom"
    default property alias content: holder.children

    visible: open || card.opacity > 0
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Component.onCompleted: if (anchorItem && anchorItem.hasPopup !== undefined) anchorItem.hasPopup = true

    // ---- keyboard cursor over the panel's rows -------------------------------
    // Rows opt in with `navigable`; the card walks its own content rather than
    // asking each panel to maintain a list.
    property int cursorIndex: -1
    property var navigableRows: []

    function collectRows(item, found) {
        for (const child of item.children) {
            if (child.navigable === true && child.visible) found.push(child)
            if (child.children) collectRows(child, found)
        }
        return found
    }
    function rebuildRows() {
        navigableRows = collectRows(holder, [])
        if (cursorIndex >= navigableRows.length) cursorIndex = navigableRows.length - 1
        syncCursor()
    }
    function syncCursor() {
        for (let i = 0; i < navigableRows.length; i++)
            navigableRows[i].cursored = (i === cursorIndex)
    }
    function moveCursor(step) {
        rebuildRows()
        if (navigableRows.length === 0) return
        cursorIndex = cursorIndex < 0
            ? (step > 0 ? 0 : navigableRows.length - 1)
            : (cursorIndex + step + navigableRows.length) % navigableRows.length
        syncCursor()
    }
    function activateCursor() {
        if (cursorIndex >= 0 && cursorIndex < navigableRows.length)
            navigableRows[cursorIndex].clicked(Qt.LeftButton)
    }
    function clearCursor() {
        cursorIndex = -1
        syncCursor()
    }
    onOpenChanged: {
        if (open) returnFocus = Hyprland.activeToplevel ? Hyprland.activeToplevel.wayland : null
        else clearCursor()
    }
    function dismiss() {
        const window = returnFocus
        shell.closePopup()
        if (window) Qt.callLater(() => window.activate())
    }

    HyprlandFocusGrab {
        active: root.open && !root.shell.focusPriming
        windows: (root.anchorWindow ? [root, root.anchorWindow] : [root]).concat(root.extraGrabWindows)
        onCleared: root.dismiss()
    }
    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1; rect.height: 1
        onAnchoring: {
            if (!root.anchorItem || !root.anchorWindow) return
            let x = root.anchorItem.width / 2 - root.width / 2
            let y = root.anchorItem.height + root.margin
            if (root.position === "bottom") y = -root.height - root.margin
            else if (root.position === "left") { x = root.anchorItem.width + root.margin; y = root.anchorItem.height / 2 - root.height / 2 }
            else if (root.position === "right") { x = -root.width - root.margin; y = root.anchorItem.height / 2 - root.height / 2 }
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, y)
            anchor.rect.x = Math.round(point.x); anchor.rect.y = Math.round(point.y)
        }
    }
    Rectangle {
        id: card
        anchors.fill: parent
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        color: root.shell.alpha(root.background, root.surfaceOpacity)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 2
        radius: root.shell.rounding
        FocusScope {
            anchors.fill: parent; anchors.margins: root.padding
            focus: root.open
            Keys.onEscapePressed: root.shell.closePopup()
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Down: root.moveCursor(1); break
                case Qt.Key_Up:   root.moveCursor(-1); break
                case Qt.Key_Return:
                case Qt.Key_Enter: root.activateCursor(); break
                default: return
                }
                event.accepted = true
            }
            Item { id: holder; anchors.fill: parent }
        }
    }
}

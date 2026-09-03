import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: root
    required property Item anchorItem
    required property var shell
    required property string popupName
    property bool popupEnabled: true
    property int contentWidth: Style.px(380)
    property int contentHeight: holder.childrenRect.height + padding * 2
    property int margin: Style.popupGap
    property int padding: Style.popupPadding
    property color background: shell.role("bg", "#0c1021")
    property color borderColor: shell.role("alt_br", shell.foreground)
    property real surfaceOpacity: 0.92
    property real borderOpacity: 0.45
    // windows that belong to this panel and must not dismiss it (submenu flyouts)
    property var extraGrabWindows: []
    readonly property bool open: popupEnabled && shell.popupName === popupName
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property string position: ["main", "alt"].includes(shell.layoutName) ? "right" : ["left", "sidebar"].includes(shell.layoutName) ? "left" : shell.layoutName === "top" ? "top" : "bottom"
    // Keep controllers/timers beside visual content. Item.data accepts both
    // QObjects and Items; visual entries still become holder.children.
    default property alias content: holder.data

    visible: open || card.opacity > 0
    color: "transparent"
    // the card never outgrows the screen it is anchored on; a panel that sizes
    // itself from content reads maxHeight to shrink its own panes first
    readonly property int maxHeight: anchorWindow && anchorWindow.screen
        ? anchorWindow.screen.height - margin * 2 : contentHeight
    implicitWidth: contentWidth
    implicitHeight: Math.min(contentHeight, maxHeight)

    Component.onCompleted: if (anchorItem && anchorItem.hasPopup !== undefined) anchorItem.hasPopup = true

    // ---- keyboard cursor over the panel's rows -------------------------------
    // Rows opt in with `navigable`; the card walks its own content rather than
    // asking each panel to maintain a list.
    property int cursorIndex: -1
    property var navigableRows: []
    onCursorIndexChanged: syncCursor()

    function collectRows(item, found) {
        for (const child of item.children) {
            if (!child.visible) continue
            if (child.navigable === true) found.push(child)
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
    }
    function selectRow(item) {
        rebuildRows()
        const index = navigableRows.indexOf(item)
        if (index >= 0) cursorIndex = index
    }
    function activateCursor() {
        if (cursorIndex >= 0 && cursorIndex < navigableRows.length)
            navigableRows[cursorIndex].clicked(Qt.LeftButton)
    }
    function resumeKeyboard() { cardFocus.forceActiveFocus() }
    function clearCursor() {
        cursorIndex = -1
        syncCursor()
    }
    onOpenChanged: if (!open) clearCursor()

    property bool wantsKeyboard: false
    property Binding typingFocus: Binding { target: root.shell; property: "popupTyping"; value: root.wantsKeyboard; when: root.open }
    property Binding cardRef: Binding { target: root.shell; property: "popupCard"; value: root; when: root.open }

    // The bar and focusable popup content both route here. Derived cards
    // override handleKey and fall back to this.
    function defaultKey(event) {
        switch (event.key) {
        case Qt.Key_Down:   moveCursor(1);    return true
        case Qt.Key_Up:     moveCursor(-1);   return true
        case Qt.Key_Return:
        case Qt.Key_Enter:  activateCursor(); return true
        case Qt.Key_Escape: shell.closePopup(); return true
        }
        return false
    }
    function handleKey(event) { return defaultKey(event) }

    HyprlandFocusGrab {
        active: root.open && !root.shell.focusPriming
        windows: (root.anchorWindow ? [root, root.anchorWindow] : [root]).concat(root.extraGrabWindows)
        onCleared: root.shell.closePopup()
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
        border.color: root.shell.alpha(root.borderColor, root.borderOpacity)
        border.width: 2
        radius: root.shell.rounding
        FocusScope {
            id: cardFocus
            anchors.fill: parent; anchors.margins: root.padding
            focus: root.open
            Keys.onPressed: event => event.accepted = root.handleKey(event)
            Item { id: holder; anchors.fill: parent }
        }
    }
}

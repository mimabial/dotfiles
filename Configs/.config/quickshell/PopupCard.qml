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
    property int contentHeight: contentHost.childrenRect.height + padding * 2
    property int margin: Style.popupGap
    // Reserve detached headers opposite the bar so they never create a bar gap.
    property int headerHeight: 0
    property int padding: Style.popupPadding
    property color background: shell.role("bg", "#0c1021")
    property color borderColor: shell.role("alt_br", shell.foreground)
    property real surfaceOpacity: Style.popupSurfaceOpacity
    property real borderOpacity: Style.popupBorderOpacity
    // windows that belong to this panel and must not dismiss it (submenu flyouts)
    property var extraGrabWindows: []
    readonly property bool open: popupEnabled && shell.popupName === popupName
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property bool centered: shell.popupCenteredName === root.popupName
    property string position: shell.barEdge
    // Keep controllers/timers beside visual content. Item.data accepts both
    // QObjects and Items; visual entries still become contentHost.children.
    default property alias content: contentHost.data
    property alias header: headerHost.data

    visible: open || cardSurface.opacity > 0
    color: "transparent"
    // The window keeps one height and the card moves inside it: a popup resized
    // under a still pointer leaves Qt with stale surface coordinates until the
    // next motion, so the following click lands on whatever used to sit there.
    property int placements: 0
    readonly property var span: {
        const screen = placements >= 0 && anchorWindow ? anchorWindow.screen : null
        if (!screen || !anchorItem) return {top: 0, height: cardHeight, anchor: 0}
        const origin = windowOrigin(), itemTop = origin.y + anchorWindow.contentItem.mapFromItem(anchorItem, 0, 0).y
        const top = !centered && position === "top" ? itemTop + anchorItem.height + margin : margin
        const bottom = !centered && position === "bottom" ? itemTop - margin : screen.height - margin
        return {top: top, height: bottom - top, anchor: itemTop + anchorItem.height / 2 - top}
    }
    // a panel that sizes itself from content reads maxHeight to shrink its own panes first
    readonly property int maxHeight: span.height
    readonly property int cardHeight: Math.min(contentHeight, maxHeight - headerHeight) + headerHeight
    readonly property int cardY: centered ? (height - cardHeight) / 2
        : position === "top" ? 0
        : position === "bottom" ? height - cardHeight
        : Math.max(0, Math.min(height - cardHeight, span.anchor - cardHeight / 2))
    implicitWidth: contentWidth
    implicitHeight: anchorWindow && anchorWindow.screen ? maxHeight : cardHeight
    mask: Region { item: card }

    function windowOrigin() {
        const screen = anchorWindow.screen, anchors = anchorWindow.anchors
        return Qt.point(anchors.left ? 0 : anchors.right ? screen.width - anchorWindow.width : (screen.width - anchorWindow.width) / 2,
            anchors.top ? 0 : anchors.bottom ? screen.height - anchorWindow.height : (screen.height - anchorWindow.height) / 2)
    }

    Component.onCompleted: {
        const hostButton = anchorItem as BarButton
        if (hostButton) hostButton.popupCards = hostButton.popupCards.concat(root)
    }

    // Rows opt in with `navigable`; the card walks its own content rather than
    // asking each panel to maintain a list.
    property int cursorIndex: -1
    property var navigableRows: []
    onCursorIndexChanged: syncKeyboardCursor()

    function collectNavigableRows(item, found) {
        for (const child of item.children) {
            if (!child.visible) continue
            if (child.navigable === true) found.push(child)
            if (child.children) collectNavigableRows(child, found)
        }
        return found
    }
    function rebuildRows() {
        navigableRows = collectNavigableRows(contentHost, [])
        if (cursorIndex >= navigableRows.length) cursorIndex = navigableRows.length - 1
        syncKeyboardCursor()
    }
    function syncKeyboardCursor() {
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
    function resumeKeyboard() { keyboardFocusScope.forceActiveFocus() }
    function clearCursor() {
        cursorIndex = -1
        syncKeyboardCursor()
    }
    onOpenChanged: if (open) ++placements; else clearCursor()

    property bool wantsKeyboard: false
    property Binding activeCardBinding: Binding { target: root.shell; property: "popupCard"; value: root; when: root.open }

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
            if (!root.anchorItem || !root.anchorWindow || !root.anchorWindow.screen) return
            // a layer surface has no x/y of its own; the compositor derives it
            // from the anchors, so redo that to express screen coordinates in window ones
            const origin = root.windowOrigin()
            let x = root.anchorItem.width / 2 - root.width / 2
            if (root.position === "left") x = root.anchorItem.width + root.margin
            else if (root.position === "right") x = -root.width - root.margin
            anchor.rect.x = Math.round(root.centered ? (root.anchorWindow.screen.width - root.width) / 2 - origin.x
                : root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, 0).x)
            anchor.rect.y = Math.round(root.span.top - origin.y)
        }
    }
    Item {
        id: card
        y: root.cardY; width: parent.width; height: root.cardHeight
        Rectangle {
            id: cardSurface
            anchors.fill: parent
            anchors.topMargin: root.position === "top" ? 0 : root.headerHeight
            anchors.bottomMargin: root.position === "top" ? root.headerHeight : 0
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            color: root.shell.alpha(root.background, root.surfaceOpacity)
            border.color: root.shell.alpha(root.borderColor, root.borderOpacity)
            border.width: root.shell.borderWidth
            radius: root.shell.rounding
            FocusScope {
                id: keyboardFocusScope
                anchors.fill: parent; anchors.margins: root.padding
                focus: root.open
                Keys.onPressed: event => event.accepted = root.handleKey(event)
                Item { id: contentHost; anchors.fill: parent }
            }
        }
        Item {
            id: headerHost
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.position === "top" ? parent.height - height : 0
            height: root.headerHeight
            opacity: cardSurface.opacity
        }
    }
}

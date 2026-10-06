import QtQuick
import QtQuick.Controls
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
    property string keyboardHint: "↑↓/Tab move · ←→ adjust · Enter · Esc"
    readonly property int keyboardHintHeight: keyboardHint ? hintText.implicitHeight + Style.sm : 0
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
    property bool leftAligned: false
    // Keep controllers/timers beside visual content. Item.data accepts both
    // QObjects and Items; visual entries still become contentHost.children.
    default property alias content: contentHost.data
    property alias header: headerHost.data

    visible: open || cardSurface.opacity > 0
    color: "transparent"
    // The window keeps one height and the card moves inside it: a popup resized
    // under a still pointer leaves Qt with stale surface coordinates until the
    // next motion, so the following click lands on whatever used to sit there.
    property int placementRevision: 0
    readonly property var availablePlacement: {
        const screen = placementRevision >= 0 && anchorWindow ? anchorWindow.screen : null
        if (!screen || !anchorItem) return {top: 0, height: cardHeight, anchor: 0}
        const origin = windowOrigin(), itemTop = origin.y + anchorWindow.contentItem.mapFromItem(anchorItem, 0, 0).y
        const top = !centered && position === "top" ? itemTop + anchorItem.height + margin : margin
        const bottom = !centered && position === "bottom" ? itemTop - margin : screen.height - margin
        return {top: top, height: Math.max(1, bottom - top), anchor: itemTop + anchorItem.height / 2 - top}
    }
    // a panel that sizes itself from content reads maxHeight to shrink its own panes first
    readonly property int maxHeight: availablePlacement.height
    readonly property int cardHeight: Math.min(contentHeight + keyboardHintHeight, maxHeight - headerHeight) + headerHeight
    property int centeredHeight: cardHeight
    readonly property int cardY: centered ? Math.max(0, (height - centeredHeight) / 2)
        : position === "top" ? 0
        : position === "bottom" ? height - cardHeight
        : Math.max(0, Math.min(height - cardHeight, availablePlacement.anchor - cardHeight / 2))
    implicitWidth: anchorWindow && anchorWindow.screen ? Math.min(contentWidth, anchorWindow.screen.width - margin * 2) : contentWidth
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
    Component.onDestruction: {
        const hostButton = root.anchorItem as BarButton
        if (hostButton) hostButton.popupCards = hostButton.popupCards.filter(card => card !== root)
    }

    // Rows opt in with `navigable`; the card walks its own content rather than
    // asking each panel to maintain a list.
    property int cursorIndex: -1
    property var navigableRows: []
    property point pointerPosition: Qt.point(-1, -1)
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
        const row = navigableRows[cursorIndex]
        const view = row ? enclosingList(row) : null
        const next = navigableRows[cursorIndex + step]
        if (view && (!next || enclosingList(next) !== view)) {
            const point = row.mapToItem(view.contentItem, row.width / 2, row.height / 2)
            const index = view.indexAt(point.x, point.y) + step
            if (index >= 0 && index < view.count) {
                view.positionViewAtIndex(index, ListView.Contain)
                Qt.callLater(() => {
                    const delegate = view.itemAtIndex(index)
                    if (!delegate) return
                    const rows = collectNavigableRows(view.contentItem, []).filter(item => descendsFrom(item, delegate))
                    if (rows.length) { selectRow(rows[step > 0 ? 0 : rows.length - 1]); revealCursor() }
                })
                return
            }
        }
        cursorIndex = cursorIndex < 0
            ? (step > 0 ? 0 : navigableRows.length - 1)
            : (cursorIndex + step + navigableRows.length) % navigableRows.length
        revealCursor()
    }
    function enclosingList(row) {
        for (let item = row.parent; item && item !== contentHost; item = item.parent)
            if (item instanceof ListView) return item
        return null
    }
    function descendsFrom(item, ancestor) {
        for (let parent = item; parent; parent = parent.parent)
            if (parent === ancestor) return true
        return false
    }
    function revealCursor() {
        if (cursorIndex < 0) return
        const row = navigableRows[cursorIndex]
        for (let item = row.parent; item && item !== root.contentItem; item = item.parent) {
            if (!(item instanceof Flickable)) continue
            const top = row.mapToItem(item.contentItem, 0, 0).y
            item.contentY = Math.max(0, Math.min(item.contentHeight - item.height,
                Math.max(top + row.height - item.height, Math.min(top, item.contentY))))
        }
    }
    function selectRow(item) {
        rebuildRows()
        const index = navigableRows.indexOf(item)
        if (index >= 0) cursorIndex = index
    }
    function followPointer(item, x, y) {
        if (!open) return
        const point = item.mapToItem(root.contentItem, x, y)
        if (point.x === pointerPosition.x && point.y === pointerPosition.y) return
        pointerPosition = point
        let index = navigableRows.indexOf(item)
        if (index < 0) { rebuildRows(); index = navigableRows.indexOf(item) }
        if (index >= 0) cursorIndex = index
    }
    function activateCursor() {
        if (cursorIndex < 0 || cursorIndex >= navigableRows.length) return
        const row = navigableRows[cursorIndex]
        if (row.activateKeyboard) row.activateKeyboard()
        else if (row.clicked) row.clicked(Qt.LeftButton)
    }
    function adjustCursor(direction) {
        const row = navigableRows[cursorIndex]
        if (!row || !row.adjustKeyboard) return false
        return row.adjustKeyboard(direction) !== false
    }
    function resumeKeyboard() { keyboardFocusScope.forceActiveFocus() }
    function clearCursor() {
        cursorIndex = -1
        syncKeyboardCursor()
    }
    onOpenChanged: if (open) ++placementRevision; else clearCursor()

    property bool wantsKeyboard: false
    property Binding activeCardBinding: Binding { target: root.shell; property: "popupCard"; value: root; when: root.open }

    // The bar and focusable popup content both route here. Derived cards
    // override handleKey and fall back to this.
    function defaultKey(event) {
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
            shell.switchPopup(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            return true
        }
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_Tab:    moveCursor(1);    return true
        case Qt.Key_Up:
        case Qt.Key_Backtab: moveCursor(-1);  return true
        case Qt.Key_Left:   return adjustCursor(-1)
        case Qt.Key_Right:  return adjustCursor(1)
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:  activateCursor(); return true
        case Qt.Key_Escape: shell.closePopup(); return true
        }
        return false
    }
    function handleKey(event) { return defaultKey(event) }

    // A window hosting bar modules outside the bar (the tray flyout) names that bar,
    // so a click on the bar reaches it instead of dismissing the popup first.
    HyprlandFocusGrab {
        active: root.open && !root.shell.focusPriming
        windows: [root, root.anchorWindow, root.anchorWindow?.bar].filter(Boolean).concat(root.extraGrabWindows)
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
            let x = root.leftAligned ? 0 : root.anchorItem.width / 2 - root.width / 2
            anchor.rect.x = Math.round(root.centered ? (root.anchorWindow.screen.width - root.width) / 2 - origin.x
                : root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, 0).x)
            anchor.rect.y = Math.round(root.availablePlacement.top - origin.y)
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
            Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
            color: root.shell.alpha(root.background, root.surfaceOpacity)
            border.color: root.shell.alpha(root.borderColor, root.borderOpacity)
            border.width: root.shell.borderWidth
            radius: root.shell.rounding
            FocusScope {
                id: keyboardFocusScope
                anchors.fill: parent; anchors.margins: root.padding
                anchors.bottomMargin: root.padding + root.keyboardHintHeight
                focus: root.open
                Keys.onPressed: event => event.accepted = root.handleKey(event)
                Flickable {
                    id: contentScroll
                    anchors.fill: parent
                    contentWidth: contentHost.width
                    contentHeight: contentHost.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                    ScrollBar.horizontal: PopupScrollBar { shell: root.shell }
                    Item {
                        id: contentHost
                        width: Math.max(contentScroll.width, root.contentWidth - root.padding * 2)
                        height: Math.max(contentScroll.height, root.contentHeight - root.padding * 2)
                    }
                }
            }
            Text {
                id: hintText
                visible: root.keyboardHint !== ""
                width: parent.width - root.padding * 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: Math.max(root.padding / 2, Style.sm)
                text: root.keyboardHint; wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, Style.caption - 2)
                color: root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
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

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property var shell
    property Item anchorItem: null
    property var handle: null
    property int contentWidth: Style.px(240)
    property int padding: Style.popupPadding
    readonly property bool open: handle !== null && anchorItem !== null
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property var openSub: null
    property Item openRow: null
    property int cursorIndex: -1
    signal picked
    signal backRequested

    property QsMenuOpener opener: QsMenuOpener { menu: root.open ? root.handle : null }
    readonly property TrayFlyout childFlyout: childLoader.item as TrayFlyout
    readonly property var grabWindows: childFlyout ? [root].concat(childFlyout.grabWindows) : [root]
    property Loader childLoader: Loader {
        active: false
    }
    property Connections childSignals: Connections {
        target: root.childFlyout
        function onPicked() { root.picked() }
        function onBackRequested() { root.closeSubmenu() }
    }

    function closeSubmenu() { openSub = null; openRow = null }
    function syncChild() {
        if (!childLoader) return
        if (!open) {
            childLoader.active = false
            return
        }
        if (openSub === null || openRow === null) {
            if (childFlyout) { childFlyout.handle = null; childFlyout.anchorItem = null }
            return
        }
        if (!childLoader.item)
            childLoader.setSource(Qt.resolvedUrl("TrayFlyout.qml"), { shell: root.shell, handle: openSub, anchorItem: openRow })
        childLoader.active = true
        if (childFlyout) { childFlyout.handle = openSub; childFlyout.anchorItem = openRow }
    }
    onOpenChanged: { if (!open) closeSubmenu(); syncChild() }
    onOpenSubChanged: syncChild()
    onOpenRowChanged: syncChild()
    onHandleChanged: { closeSubmenu(); cursorIndex = -1 }
    Component.onCompleted: syncChild()
    function moveCursor(step) {
        for (let i = 0, next = cursorIndex; i < entries.count; i++) {
            next = next < 0 ? (step > 0 ? 0 : entries.count - 1)
                : (next + step + entries.count) % entries.count
            const menu = root.opener.children[next]
            if (menu && menu.enabled && !menu.isSeparator) {
                cursorIndex = next
                return
            }
        }
    }
    function activateCursor() {
        if (cursorIndex < 0) moveCursor(1)
        const menu = root.opener.children[cursorIndex]
        if (!menu) return
        if (menu.hasChildren) {
            openSub = menu
            const entry = entries.itemAt(cursorIndex)
            openRow = entry ? entry.children.find(child => child instanceof PopupRow) : null
        } else {
            menu.triggered()
            picked()
        }
    }
    function handleKey(event) {
        if (childFlyout && childFlyout.open) return childFlyout.handleKey(event)
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { backRequested(); return true }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { moveCursor(1); return true }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { moveCursor(-1); return true }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { activateCursor(); return true }
        return false
    }
    // see StartMenuFlyout: equal-size sibling rows do not re-trigger anchoring
    onAnchorItemChanged: if (root.open) anchor.updateAnchor()

    visible: open
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

    // see StartMenuFlyout: row-sized rect so the compositor can flip this level
    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.FlipX | PopupAdjustment.Slide
        edges: Edges.Top | Edges.Right
        gravity: Edges.Bottom | Edges.Right
        rect.width: root.anchorItem ? root.anchorItem.width : 1
        rect.height: root.anchorItem ? root.anchorItem.height : 1
        onAnchoring: {
            if (!root.anchorItem || !root.anchorWindow) return
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, 0, 0)
            anchor.rect.x = Math.round(point.x); anchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: event => {
            if (root.shell.popupCard) event.accepted = root.shell.popupCard.handleKey(event)
        }
        color: root.shell.alpha(root.shell.role("bg", "#0c1021"), Style.popupSurfaceOpacity)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 1
        radius: root.shell.rounding

        Column {
            id: flyColumn
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.padding
            spacing: 2
            Repeater {
                id: entries
                model: root.opener.children
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    width: flyColumn.width
                    implicitHeight: entry.modelData.isSeparator ? sep.implicitHeight : row.implicitHeight

                    PopupSeparator { id: sep; visible: entry.modelData.isSeparator; shell: root.shell; width: parent.width }

                    PopupRow {
                        id: row
                        visible: !entry.modelData.isSeparator
                        enabled: entry.modelData.enabled
                        cursored: root.cursorIndex === entry.index
                        width: parent.width; shell: root.shell
                        title: entry.modelData.text
                        iconSource: entry.modelData.icon
                        active: root.openSub === entry.modelData
                        color: row.highlight
                        value: entry.modelData.hasChildren ? "›"
                            : entry.modelData.buttonType === QsMenuButtonType.CheckBox
                                ? (entry.modelData.checkState === Qt.Checked ? "✓" : "")
                                : entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                    ? (entry.modelData.checkState === Qt.Checked ? "◉" : "○")
                                    : ""
                        opacity: entry.modelData.enabled ? 1 : .4
                        onHoveredChanged: {
                            if (!hovered || !entry.modelData.enabled) return
                            root.openSub = entry.modelData.hasChildren ? entry.modelData : null
                            root.openRow = entry.modelData.hasChildren ? row : null
                        }
                        onClicked: {
                            if (!entry.modelData.enabled) return
                            if (entry.modelData.hasChildren) {
                                const same = root.openSub === entry.modelData
                                root.openSub = same ? null : entry.modelData
                                root.openRow = same ? null : row
                                return
                            }
                            entry.modelData.triggered()
                            root.picked()
                        }
                    }
                }
            }
            Text {
                width: parent.width; text: "↑↓ move · → open · ← back · Esc"
                wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, Style.caption - 2)
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }
    }
}

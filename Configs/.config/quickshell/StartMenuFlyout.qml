pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons

PopupWindow {
    id: root
    required property var shell
    property var menus: ({})
    property string menuId: ""
    property Item anchorItem: null
    property int contentWidth: Style.px(230)
    property int padding: Style.popupPadding
    readonly property bool open: menuId !== "" && anchorItem !== null && items.length > 0
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property string openSubId: ""
    property Item openRow: null
    property int cursorIndex: -1
    signal actionTriggered(string target, bool keepOpen)
    signal dismissed()
    readonly property bool hovered: flyHover.hovered

    readonly property var items: {
        const menu = menus[menuId]
        if (!menu) return []
        const out = []
        for (const item of menu.items) {
            if (item.target === "search_all" || item.target === "main_apps") continue
            out.push(item)
        }
        return out
    }
    function labelIcon(label) { const m = label.match(/^(\S+)\s{2,}/); return m ? m[1] : "" }
    function labelText(label) { const m = label.match(/^\S+\s{2,}(.*)$/); return m ? m[1] : label }
    function closeSubmenu() { openSubId = ""; openRow = null }
    function moveCursor(step) {
        if (items.length === 0) return
        cursorIndex = cursorIndex < 0 ? (step > 0 ? 0 : items.length - 1) : (cursorIndex + step + items.length) % items.length
    }
    function activateCursor() {
        const item = items[cursorIndex]
        if (!item) moveCursor(1)
        else if (item.kind === "submenu") { openSubId = item.target; openRow = rows.itemAt(cursorIndex) }
        else actionTriggered(item.target, false)
    }
    function togglesInPlace(item) { return !!item && item.kind !== "submenu" && shell.menuTargetActive(item.target) !== undefined }
    function cursorToggleTarget() { return togglesInPlace(items[cursorIndex]) ? items[cursorIndex].target : "" }
    function handleKey(event) {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Escape) { dismissed(); return true }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { moveCursor(1); return true }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { moveCursor(-1); return true }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateCursor(); return true }
        return false
    }
    onOpenChanged: if (!open) closeSubmenu()
    onMenuIdChanged: { closeSubmenu(); cursorIndex = -1 }
    onAnchorItemChanged: if (root.open) anchor.updateAnchor()
    onVisibleChanged: if (!visible && open) dismissed()

    visible: open
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

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
        color: root.shell.alpha(Style.popupTinted(root.shell.role("bg", "#0c1021")), Style.popupSurfaceOpacity)
        radius: root.shell.rounding

        HoverHandler { id: flyHover }

        Column {
            id: flyColumn
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.padding
            spacing: Style.xxs
            Repeater {
                id: rows
                model: root.items
                delegate: PopupRow {
                    id: row
                    required property var modelData
                    required property int index
                    width: flyColumn.width; height: Style.popupRowHeight; shell: root.shell
                    icon: root.labelIcon(modelData.label)
                    title: root.labelText(modelData.label)
                    valueWidth: Style.px(18)
                    readonly property bool checked: root.shell.menuTargetActive(modelData.target) ?? modelData.checked
                    cursored: root.cursorIndex === row.index
                    active: modelData.kind === "submenu" && root.openSubId === modelData.target
                    value: modelData.chevron || (checked ? "✓" : "")
                    onHoveredChanged: {
                        if (!hovered) return
                        root.cursorIndex = row.index
                        if (modelData.kind === "submenu") { root.openSubId = modelData.target; root.openRow = row }
                        else { root.openSubId = ""; root.openRow = null }
                    }
                    onClicked: button => {
                        if (modelData.kind === "submenu") {
                            const same = root.openSubId === modelData.target
                            root.openSubId = same ? "" : modelData.target
                            root.openRow = same ? null : row
                            return
                        }
                        root.actionTriggered(modelData.target, button === Qt.RightButton && root.togglesInPlace(modelData))
                    }
                }
            }
            Text {
                width: parent.width
                textFormat: Text.StyledText
                text: Commons.Util.keyHintMarkup("↑↓ Move  → Open  " + (root.items.some(item => root.togglesInPlace(item)) ? "Space Toggle  " : "")
                    + "← Back  Esc", root.shell.mutedText)
                wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: Math.max(10, Style.caption - 2)
                color: root.shell.accent
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }
    }
}

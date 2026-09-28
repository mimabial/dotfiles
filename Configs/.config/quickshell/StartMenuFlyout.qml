pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property var shell
    property var menus: ({})
    property string menuId: ""
    property Item anchorItem: null
    property int contentWidth: Style.px(230)
    property int padding: Style.popupPadding
    property string mappedMenuId: ""
    readonly property bool open: menuId !== "" && anchorItem !== null && items.length > 0
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property string openSubId: ""
    property Item openRow: null
    property bool openLeft: false
    signal actionTriggered(string target)
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
    function remapMenu() {
        mappedMenuId = ""
        if (menuId !== "") showNextMenu.restart()
    }
    onOpenChanged: if (!open) closeSubmenu()
    onMenuIdChanged: { closeSubmenu(); remapMenu() }
    onMenusChanged: remapMenu()
    onAnchorItemChanged: if (root.open) anchor.updateAnchor()
    onVisibleChanged: if (!visible && open && mappedMenuId === menuId) dismissed()
    Timer { id: showNextMenu; interval: 0; onTriggered: root.mappedMenuId = root.menuId }

    visible: open && mappedMenuId === menuId
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.FlipX | PopupAdjustment.Slide
        edges: Edges.Top | (root.openLeft ? Edges.Left : Edges.Right)
        gravity: Edges.Bottom | (root.openLeft ? Edges.Left : Edges.Right)
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
        color: root.shell.alpha(root.shell.role("bg", "#0c1021"), 0.94)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 1
        radius: root.shell.rounding

        HoverHandler { id: flyHover }

        Column {
            id: flyColumn
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.padding
            spacing: Style.xxs
            Repeater {
                model: root.items
                delegate: PopupRow {
                    id: row
                    required property var modelData
                    width: flyColumn.width; height: Style.popupRowHeight; shell: root.shell
                    icon: root.labelIcon(modelData.label)
                    title: root.labelText(modelData.label)
                    valueWidth: Style.px(18)
                    readonly property bool checked: root.shell.menuTargetActive(modelData.target) ?? modelData.checked
                    active: modelData.kind === "submenu" && root.openSubId === modelData.target
                    color: row.highlight
                    value: modelData.chevron || (checked ? "✓" : "")
                    onHoveredChanged: {
                        if (!hovered) return
                        if (modelData.kind === "submenu") { root.openSubId = modelData.target; root.openRow = row }
                        else { root.openSubId = ""; root.openRow = null }
                    }
                    onClicked: {
                        if (modelData.kind === "submenu") {
                            const same = root.openSubId === modelData.target
                            root.openSubId = same ? "" : modelData.target
                            root.openRow = same ? null : row
                            return
                        }
                        root.actionTriggered(modelData.target)
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

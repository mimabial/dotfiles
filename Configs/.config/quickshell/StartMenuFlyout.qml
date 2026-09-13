pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// One cascade level of the menu.d tree, anchored beside the row that opened it.
// Chained like TrayFlyout: the next level binds to this openSubId/openRow.
PopupWindow {
    id: root
    required property var shell
    property var menus: ({})
    property string menuId: ""
    property Item anchorItem: null
    property int contentWidth: Style.px(230)
    property int padding: Style.popupPadding
    readonly property bool open: menuId !== "" && anchorItem !== null
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property string openSubId: ""
    property Item openRow: null
    // preferred cascade side: away from the bar, so the common case never flips
    property bool openLeft: false
    signal actionTriggered(string target)
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
    function selectedTarget(target) {
        const value = String(target || "")
        const layoutPrefix = "style_bar_layout_"
        if (value.indexOf(layoutPrefix) === 0)
            return root.shell.layoutName === value.slice(layoutPrefix.length)
        const cornerPrefix = "style_expose_hot_corner_"
        if (value.indexOf(cornerPrefix) === 0)
            return root.shell.exposeConfig.hotCornerEnabled
                && root.shell.exposeConfig.hotCornerPosition === value.slice(cornerPrefix.length)
        return false
    }

    onOpenChanged: if (!open) { openSubId = ""; openRow = null }
    onMenuIdChanged: { openSubId = ""; openRow = null }
    // Switching between two equal-length sibling submenus changes nothing the
    // anchor watches, so it would keep the previous row's y.
    onAnchorItemChanged: if (root.open) anchor.updateAnchor()

    visible: open
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

    // the rect is the row itself, so the compositor can mirror this level about
    // it when the preferred side runs out of screen. Flip is tried before slide,
    // so a cramped level lands beside its parent instead of on top of it
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
        color: root.shell.alpha(root.shell.role("bg", "#0c1021"), 0.94)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 1
        radius: root.shell.rounding

        HoverHandler { id: flyHover }

        Column {
            id: flyColumn
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.padding
            spacing: 2
            Repeater {
                model: root.items
                delegate: PopupRow {
                    id: row
                    required property var modelData
                    width: flyColumn.width; shell: root.shell
                    icon: root.labelIcon(modelData.label)
                    title: root.labelText(modelData.label)
                    valueWidth: Style.px(18)
                    selected: root.selectedTarget(modelData.target)
                    active: modelData.kind === "submenu" ? root.openSubId === modelData.target : selected
                    color: row.highlight
                    value: modelData.chevron || (selected ? "✓" : "")
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
        }
    }
}

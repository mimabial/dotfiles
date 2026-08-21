import QtQuick
import Quickshell

// One cascade level of the menu.d tree, anchored to the right of the row that
// opened it. Chained like TrayFlyout: the next level binds to this openSubId/openRow.
PopupWindow {
    id: root
    required property var shell
    property var menus: ({})
    property string menuId: ""
    property Item anchorItem: null
    property int contentWidth: 230
    property int padding: Style.popupPadding
    readonly property bool open: menuId !== "" && anchorItem !== null
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property string openSubId: ""
    property Item openRow: null
    signal actionTriggered(string target)

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

    onOpenChanged: if (!open) { openSubId = ""; openRow = null }
    onMenuIdChanged: { openSubId = ""; openRow = null }

    visible: open
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1; rect.height: 1
        onAnchoring: {
            if (!root.anchorItem || !root.anchorWindow) return
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width, 0)
            anchor.rect.x = Math.round(point.x); anchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.shell.alpha(root.shell.role("bg", "#0c1021"), 0.94)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 1
        radius: root.shell.rounding

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
                    active: modelData.kind === "submenu" && root.openSubId === modelData.target
                    color: row.highlight
                    value: modelData.kind === "submenu" ? "❯" : ""
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

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "../dock" as Dock
import ".."

PopupCard {
    id: root
    property var items: []
    property var path: []
    property int keyLevel: 0
    property var keyRow: null
    leftAligned: true
    keyboardHint: ""
    contentWidth: Commons.Style.space(240)
    contentHeight: entries.implicitHeight + padding * 2
    padding: Commons.Style.space(4)
    background: Commons.Color.menu.background
    borderColor: Commons.Color.menu.border
    extraGrabWindows: Array.from({ length: flyouts.count }, (_, index) => flyouts.objectAt(index))
    onOpenChanged: { path = []; select(0, null) }
    function run(item) { shell.closePopup(); typeof item.run === "function" ? item.run() : shell.run(item.run) }
    function depth(items) { return Math.max(0, ...items.filter(item => item?.submenu).map(item => 1 + depth(item.submenu))) }
    function rowsAt(level) { return collectNavigableRows(level ? (flyouts.objectAt(level - 1) as Flyout).column : entries, []) }
    function select(level, row) { keyLevel = level; keyRow = row }
    function hover(level, row, item) {
        select(level, row)
        const branch = item?.submenu ? { row, items: item.submenu } : null
        if (path[level]?.row === row || (!branch && path.length === level)) return
        path = path.slice(0, level).concat(branch ? [branch] : [])
    }
    function move(step) {
        const rows = rowsAt(keyLevel), index = rows.indexOf(keyRow)
        if (!rows.length) return
        select(keyLevel, rows[index < 0 ? (step > 0 ? 0 : rows.length - 1) : (index + step + rows.length) % rows.length])
        path = path.slice(0, keyLevel)
    }
    function enter() {
        if (!keyRow) return
        if (!keyRow.item.submenu) return run(keyRow.item)
        hover(keyLevel, keyRow, keyRow.item)
        select(keyLevel + 1, rowsAt(keyLevel + 1)[0] ?? null)
    }
    function back() {
        select(keyLevel - 1, path[keyLevel - 1].row)
        path = path.slice(0, keyLevel)
    }
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_Tab: move(1); return true
        case Qt.Key_Up: case Qt.Key_Backtab: move(-1); return true
        case Qt.Key_Right: if (keyRow?.item.submenu) enter(); return true
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: enter(); return true
        case Qt.Key_Left: if (keyLevel) back(); return true
        case Qt.Key_Escape: keyLevel ? back() : shell.closePopup(); return true
        }
        return false
    }

    component Entries: Column {
        id: column
        required property var menu
        required property int level
        required property var entries
        Repeater {
            model: column.entries
            Column {
                id: entry
                required property var modelData
                Dock.DockMenuDivider { visible: !entry.modelData; menuWidth: column.width }
                Dock.DockMenuRow {
                    id: row
                    readonly property var item: entry.modelData
                    visible: !!item
                    menuWidth: column.width
                    text: item?.text ?? ""
                    readonly property bool marked: typeof item?.checked === "function" ? item.checked() : !!item?.checked
                    glyph: marked ? "✓" : item?.glyph ?? ""
                    textColor: marked ? Commons.Color.bar.active : Commons.Color.menu.text
                    shortcut: item?.shortcut ?? ""
                    disabled: !item?.run && !item?.submenu
                    cursored: column.menu.keyRow === row
                    highlighted: column.menu.path[column.level]?.row === row
                    onHoveredChanged: if (hovered) column.menu.hover(column.level, row, item)
                    onTriggered: item.submenu ? column.menu.hover(column.level, row, item) : column.menu.run(item)
                }
            }
        }
    }
    component Flyout: PopupWindow {
        id: flyout
        required property var menu
        required property int index
        readonly property alias column: submenu
        readonly property var branch: menu.path[index] ?? null
        property var shownBranch: null
        visible: menu.open && branch !== null && shownBranch === branch
        onBranchChanged: { shownBranch = null; if (branch) remap.restart() }
        color: "transparent"
        implicitWidth: menu.contentWidth
        implicitHeight: submenu.implicitHeight + menu.padding * 2
        anchor {
            window: flyout.branch ? flyout.branch.row.QsWindow.window : null
            adjustment: PopupAdjustment.FlipX | PopupAdjustment.Slide
            edges: Edges.Top | Edges.Right
            gravity: Edges.Bottom | Edges.Right
            rect.width: flyout.branch ? flyout.branch.row.width : 1
            rect.height: flyout.branch ? flyout.branch.row.height : 1
            onAnchoring: {
                if (!flyout.branch) return
                const point = flyout.anchor.window.contentItem.mapFromItem(flyout.branch.row, 0, 0)
                flyout.anchor.rect.x = Math.round(point.x)
                flyout.anchor.rect.y = Math.round(point.y - flyout.menu.padding)
            }
        }
        Timer { id: remap; interval: 0; onTriggered: flyout.shownBranch = flyout.branch }
        Rectangle {
            anchors.fill: parent
            color: flyout.menu.shell.alpha(flyout.menu.background, flyout.menu.surfaceOpacity)
            border.color: flyout.menu.shell.alpha(flyout.menu.borderColor, flyout.menu.borderOpacity)
            border.width: flyout.menu.shell.borderWidth
            radius: flyout.menu.shell.rounding
            Entries {
                id: submenu
                x: flyout.menu.padding; y: flyout.menu.padding; width: parent.width - 2 * x
                menu: flyout.menu; level: flyout.index + 1; entries: flyout.branch?.items ?? []
            }
        }
    }

    Entries { id: entries; width: parent.width; menu: root; level: 0; entries: root.items }
    Instantiator { id: flyouts; model: root.depth(root.items); delegate: Flyout { menu: root } }
}

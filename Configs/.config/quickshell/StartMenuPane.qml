pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Column {
    id: root
    required property var shell
    property var menus: ({})
    property int totalHeight: 200
    property string openSubId: ""
    property Item openRow: null
    property int cursorIndex: -1
    property bool cursorShown: false
    onItemsChanged: cursorIndex = Math.min(cursorIndex, items.length - 1)
    signal action(string target)
    readonly property int unconstrainedHeight: menuHeader.height + root.spacing + menuList.contentHeight
    readonly property bool hovered: paneHover.hovered
    readonly property bool overflowing: menuList.contentHeight > menuList.height
    spacing: Style.sm
    height: totalHeight

    readonly property var rofiOnlyTargets: ["search_all", "main_apps"]
    readonly property var items: {
        const menu = menus["main"]
        if (!menu) return []
        const out = []
        for (const item of menu.items) {
            if (rofiOnlyTargets.includes(item.target)) continue
            out.push(item)
        }
        return out
    }
    function labelIcon(label) { const m = label.match(/^(\S+)\s{2,}/); return m ? m[1] : "" }
    function labelText(label) { const m = label.match(/^\S+\s{2,}(.*)$/); return m ? m[1] : label }
    function reset() { openSubId = ""; openRow = null }
    function moveCursor(step) {
        cursorIndex = Math.max(0, Math.min(items.length - 1, cursorIndex + step))
        menuList.positionViewAtIndex(cursorIndex, ListView.Contain)
    }
    function openCursorSubmenu() {
        const item = items[cursorIndex]
        if (!item || item.kind !== "submenu") return false
        openSubId = item.target; openRow = menuList.itemAtIndex(cursorIndex)
        return true
    }
    function activateCursor() {
        const item = items[cursorIndex]
        if (item && !openCursorSubmenu()) action(item.target)
    }

    HoverHandler { id: paneHover }
    PopupSection { id: menuHeader; shell: root.shell; text: "MENU" }
    ListView {
        id: menuList
        width: parent.width
        height: root.totalHeight - menuHeader.height - root.spacing
        clip: true
        spacing: 2
        model: root.items
        ScrollBar.vertical: PopupScrollBar { shell: root.shell }
        delegate: PopupRow {
            id: row
            required property var modelData
            required property int index
            readonly property string cursorSection: "menu"
            readonly property int cursorSlot: index
            cursored: root.cursorShown && root.cursorIndex === index
            width: menuList.width; shell: root.shell
            rightInset: root.overflowing ? Style.md : 0
            icon: root.labelIcon(modelData.label)
            title: root.labelText(modelData.label)
            valueWidth: Style.px(18)
            active: modelData.kind === "submenu" && root.openSubId === modelData.target
            value: modelData.chevron
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
                root.action(modelData.target)
            }
        }
    }
}

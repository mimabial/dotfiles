import QtQuick

// Top level of the rofi menu.d tree (menutree --dump-json). Submenu rows open
// cascading StartMenuFlyout windows chained off openSubId/openRow.
Column {
    id: root
    required property var shell
    property var menus: ({})
    property int totalHeight: 200
    property string openSubId: ""
    property Item openRow: null
    signal action(string target)
    spacing: Style.sm
    height: totalHeight

    // search_all/main_apps are rofi-only: the popup has its own search and app list
    readonly property var items: {
        const menu = menus["main"]
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
    function reset() { openSubId = ""; openRow = null }

    PopupSection { id: menuHeader; shell: root.shell; text: "MENU" }
    ListView {
        id: menuList
        width: parent.width
        height: root.totalHeight - menuHeader.height - root.spacing
        clip: true
        spacing: 2
        model: root.items
        delegate: PopupRow {
            id: row
            required property var modelData
            width: menuList.width; shell: root.shell
            icon: root.labelIcon(modelData.label)
            title: root.labelText(modelData.label)
            active: modelData.kind === "submenu" && root.openSubId === modelData.target
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
                root.action(modelData.target)
            }
        }
    }
}

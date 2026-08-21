import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "barlayout"
    contentWidth: 320
    contentHeight: layoutColumn.implicitHeight + padding * 2
    property var layouts: []
    function title(name) { return name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, " ") }
    function refresh() { if (!listRead.running) listRead.running = true }
    onOpenChanged: if (open) refresh()
    property Process listRead: Process { command: ["hyprshell", "quickshell/layout", "list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.layouts = String(text).trim().split("\n").filter(Boolean) } }

    Column {
        id: layoutColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.xs
        PopupSection { shell: root.shell; text: "BAR" }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰂵"; title: "Transparent background"; detail: active ? "Enabled" : "Disabled"; active: root.shell.store.barTransparent; onClicked: root.shell.toggleBarTransparency() }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "LAYOUT" }
        Repeater {
            model: root.layouts
            PopupRow {
                required property string modelData
                width: layoutColumn.width; shell: root.shell; icon: root.shell.barLayoutIcon(modelData); title: root.title(modelData)
                detail: active ? "Active" : "Switch to this layout"
                active: root.shell.layoutName === modelData
                onClicked: root.shell.run(["hyprshell", "quickshell/layout", "set", modelData])
            }
        }
    }
}

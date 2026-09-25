pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "barlayout"
    contentWidth: Style.px(320)
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
        PopupRow { width: parent.width; shell: root.shell; icon: "󰂵"; title: "Transparent background"; detail: active ? "Enabled" : "Disabled"; active: root.shell.prefs.barTransparent; onClicked: root.shell.toggleBarTransparency() }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰽙"; title: "Background blur"; detail: active ? "Enabled" : "Disabled"; active: root.shell.prefs.barBlur; onClicked: root.shell.toggleBarBlur() }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰹞"; title: "Floating bar"; detail: active ? root.shell.barFloatGap + " px gap" : "Disabled"; active: root.shell.prefs.barFloating; onClicked: root.shell.toggleBarFloating() }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "LAYOUT" }
        Repeater {
            model: root.layouts
            PopupRow {
                required property string modelData
                width: layoutColumn.width; shell: root.shell; icon: ""; title: root.title(modelData)
                detail: active ? "Active" : "Switch to this layout"
                active: root.shell.layoutName === modelData
                onClicked: { root.shell.closePopup(); root.shell.run(["hyprshell", "quickshell/layout", "set", modelData]) }
            }
        }
    }
}

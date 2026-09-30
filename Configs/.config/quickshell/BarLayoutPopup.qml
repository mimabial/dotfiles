pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "Opacity.js" as Opacity

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
        PopupRow { width: parent.width; shell: root.shell; icon: "󰽙"; title: "Background blur"; detail: active ? "Enabled" : "Disabled"; active: root.shell.prefs.barBlur; onClicked: root.shell.toggleBarBlur() }
        PopupRow {
            width: parent.width; shell: root.shell; icon: "󰃟"; title: "Opacity"; interactive: false; rightInset: opacitySelect.width + Style.sm
            PopupSelect {
                id: opacitySelect
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                width: Style.px(172); shell: root.shell
                choices: [{ label: "Auto (Workflow)", value: -1 }].concat(Opacity.presets.map(preset => ({ label: Opacity.label(preset), value: preset.value })))
                selectedIndex: root.shell.prefs.barOpacity < 0 ? 0 : 1 + Opacity.presets.indexOf(Opacity.nearest(root.shell.prefs.barOpacity))
                onActivated: index => root.shell.prefs.barOpacity = opacitySelect.choices[index].value
            }
        }
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

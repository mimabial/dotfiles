pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "colormode"
    contentWidth: Style.px(320)
    contentHeight: colorColumn.implicitHeight + padding * 2
    property string source: "theme"
    property string mode: "dark"
    readonly property var modes: [{name:"Auto", value:"auto", icon:"󰔎"}, {name:"Dark", value:"dark", icon:""}, {name:"Light", value:"light", icon:"󰖙"}]
    function load(raw) {
        const state = String(raw)
        const sourceMatch = state.match(/(?:^|\n)selected_color_source=["']?([^"'\n]+)/)
        const modeMatch = state.match(/(?:^|\n)selected_color_mode=["']?([^"'\n]+)/)
        const modeByStateValue = {"1":"auto", "2":"dark", "3":"light"}
        source = sourceMatch ? sourceMatch[1] : "theme"
        mode = modeByStateValue[modeMatch ? modeMatch[1] : "2"] || "dark"
    }
    function apply(nextSource, nextMode) { if (nextSource === source && nextMode === mode) return; shell.run(["hyprshell", "theme/color-mode", "--set", nextSource, nextMode]) }
    property FileView stateFile: FileView { path: root.shell.home + "/.local/state/hypr/staterc"; watchChanges: true; onLoaded: root.load(text()); onFileChanged: reload() }

    component SourceRow: Item {
        id: sourceRow
        required property string rowSource
        required property string icon
        required property string title
        required property string detail
        signal previous()
        signal next()
        implicitHeight: row.implicitHeight
        PopupRow { id: row; anchors.fill: parent; shell: root.shell; icon: sourceRow.icon; title: sourceRow.title; detail: sourceRow.detail; active: root.source === sourceRow.rowSource; rightInset: actions.width + Style.xs; onClicked: root.apply(sourceRow.rowSource, root.mode) }
        Row {
            id: actions; anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter; spacing: Style.xs
            PopupIconButton { shell: root.shell; glyph: "󰒮"; hint: "Previous " + sourceRow.title.toLowerCase(); onClicked: sourceRow.previous() }
            PopupIconButton { shell: root.shell; glyph: "󰒭"; hint: "Next " + sourceRow.title.toLowerCase(); onClicked: sourceRow.next() }
        }
    }

    Column {
        id: colorColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "COLOR SOURCE" }
            SourceRow { width: parent.width; rowSource: "theme"; icon: "󰏘"; title: "Theme"; detail: "Use the theme palette"; onPrevious: root.shell.run(["hyprshell", "theme/theme.switch", "-p", "--quiet"]); onNext: root.shell.run(["hyprshell", "theme/theme.switch", "-n", "--quiet"]) }
            SourceRow { width: parent.width; rowSource: "wallpaper"; icon: "󰸉"; title: "Wallpaper"; detail: "Generate colors from the wallpaper"; onPrevious: root.shell.run(["hyprshell", "wallpaper", "previous", "--global"]); onNext: root.shell.run(["hyprshell", "wallpaper", "next", "--global"]) }
        }
        PopupSeparator { shell: root.shell }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "VARIANT" }
            Row {
                width: parent.width; spacing: Style.sm
                Repeater { model: root.modes; PopupTab { required property var modelData; width: (colorColumn.width - Style.sm * 2) / 3; shell: root.shell; icon: modelData.icon; text: modelData.name; selected: modelData.value === root.mode; onClicked: root.apply(root.source, modelData.value) } }
            }
        }
    }
}

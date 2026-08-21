import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "colormode"
    contentWidth: 320
    contentHeight: colorColumn.implicitHeight + padding * 2
    property string source: "theme"
    property string mode: "dark"
    readonly property var modes: [{name:"Auto", value:"auto", icon:"󰔎"}, {name:"Dark", value:"dark", icon:""}, {name:"Light", value:"light", icon:"󰖙"}]
    function load(raw) { const text = String(raw), sourceMatch = text.match(/(?:^|\n)selected_color_source=["']?([^"'\n]+)/), modeMatch = text.match(/(?:^|\n)selected_color_mode=["']?([^"'\n]+)/); source = sourceMatch ? sourceMatch[1] : "theme"; mode = ({"1":"auto", "2":"dark", "3":"light"})[modeMatch ? modeMatch[1] : "2"] || "dark" }
    function apply(nextSource, nextMode) { if (nextSource === source && nextMode === mode) return; shell.run(["hyprshell", "theme/color-mode", "--set", nextSource, nextMode]) }
    property FileView stateFile: FileView { path: root.shell.home + "/.local/state/hypr/staterc"; watchChanges: true; onLoaded: root.load(text()); onFileChanged: reload() }

    Column {
        id: colorColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm
        PopupSection { shell: root.shell; text: "COLOR SOURCE" }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰏘"; title: "Theme"; detail: "Use the theme palette"; active: root.source === "theme"; onClicked: root.apply("theme", root.mode) }
        PopupRow { width: parent.width; shell: root.shell; icon: "󰸉"; title: "Wallpaper"; detail: "Generate colors from the wallpaper"; active: root.source === "pywal"; onClicked: root.apply("pywal", root.mode) }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "VARIANT" }
        Repeater { model: root.modes; PopupRow { required property var modelData; width: colorColumn.width; shell: root.shell; icon: modelData.icon; title: modelData.name; detail: modelData.value === root.mode ? "Active" : ""; active: modelData.value === root.mode; onClicked: root.apply(root.source, modelData.value) } }
    }
}

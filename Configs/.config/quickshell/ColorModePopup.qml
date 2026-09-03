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
    function load(raw) { const text = String(raw), sourceMatch = text.match(/(?:^|\n)selected_color_source=["']?([^"'\n]+)/), modeMatch = text.match(/(?:^|\n)selected_color_mode=["']?([^"'\n]+)/); source = sourceMatch ? sourceMatch[1] : "theme"; mode = ({"1":"auto", "2":"dark", "3":"light"})[modeMatch ? modeMatch[1] : "2"] || "dark" }
    function apply(nextSource, nextMode) { if (nextSource === source && nextMode === mode) return; shell.run(["hyprshell", "theme/color-mode", "--set", nextSource, nextMode]) }
    property FileView stateFile: FileView { path: root.shell.home + "/.local/state/hypr/staterc"; watchChanges: true; onLoaded: root.load(text()); onFileChanged: reload() }

    component NavButton: BarButton {
        shell: root.shell; implicitWidth: Style.controlHeight; implicitHeight: Style.controlHeight
        radius: shell.rounding; fill: shell.alpha(shell.foreground, .07); outline: shell.alpha(shell.role("br", shell.foreground), .3); fontSize: Style.subtitle
    }
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
            NavButton { text: "󰒮"; tooltip: "Previous " + sourceRow.title.toLowerCase(); onClicked: sourceRow.previous() }
            NavButton { text: "󰒭"; tooltip: "Next " + sourceRow.title.toLowerCase(); onClicked: sourceRow.next() }
        }
    }
    component ModeButton: BarButton {
        // opt into the card's row walk through the base property, not a shadow of it
        keyboardEnabled: true
        shell: root.shell; radius: shell.rounding; fontSize: Style.bodySmall
        fill: active ? shell.alpha(shell.role("act_bg", shell.accent), .3) : shell.alpha(shell.foreground, .07)
        outline: active ? shell.alpha(shell.role("act_br", shell.accent), .65) : cursored ? shell.hoverEdge(.85) : shell.alpha(shell.role("br", shell.foreground), .25)
    }

    Column {
        id: colorColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm
        PopupSection { shell: root.shell; text: "COLOR SOURCE" }
        SourceRow { width: parent.width; rowSource: "theme"; icon: "󰏘"; title: "Theme"; detail: "Use the theme palette"; onPrevious: root.shell.run(["hyprshell", "theme/theme.switch", "-p", "--quiet"]); onNext: root.shell.run(["hyprshell", "theme/theme.switch", "-n", "--quiet"]) }
        SourceRow { width: parent.width; rowSource: "pywal"; icon: "󰸉"; title: "Wallpaper"; detail: "Generate colors from the wallpaper"; onPrevious: root.shell.run(["hyprshell", "wallpaper", "previous", "--global"]); onNext: root.shell.run(["hyprshell", "wallpaper", "next", "--global"]) }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "VARIANT" }
        Row {
            width: parent.width; height: Style.controlHeight; spacing: Style.xs
            Repeater { model: root.modes; ModeButton { required property var modelData; width: (colorColumn.width - Style.xs * 2) / 3; height: parent.height; text: modelData.icon + "  " + modelData.name; active: modelData.value === root.mode; onClicked: root.apply(root.source, modelData.value) } }
        }
    }
}

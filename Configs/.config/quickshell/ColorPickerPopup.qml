import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PopupCard {
    id: root
    popupName: "colorpicker"
    contentWidth: Style.px(320)
    contentHeight: colorColumn.implicitHeight + padding * 2
    property var colors: []
    function load(raw) { colors = String(raw).trim().split("\n").filter(color => /^#[0-9a-fA-F]{6}$/.test(color)) }
    function copy(color) { shell.run(["wl-copy", color]); shell.closePopup() }
    function pick() { shell.closePopup(); shell.run(["hyprshell", "rofi/color-picker"]) }
    property FileView colorFile: FileView { path: root.shell.home + "/.cache/colorpicker/colors"; watchChanges: true; printErrors: false; onLoaded: root.load(text()); onFileChanged: reload() }

    Column {
        id: colorColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm
        PopupSection { shell: root.shell; text: "RECENT COLORS" }
        GridLayout {
            width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
            Repeater { model: root.colors; PopupRow { required property string modelData; Layout.fillWidth: true; shell: root.shell; icon: "●"; iconColor: modelData; title: modelData.toUpperCase(); detail: "Copy to clipboard"; onClicked: root.copy(modelData) } }
            PopupRow { visible: root.colors.length === 0; Layout.columnSpan: 2; Layout.fillWidth: true; enabled: false; shell: root.shell; icon: "󰀦"; title: "No saved colors" }
        }
        PopupSeparator { shell: root.shell }
        PopupRow { width: parent.width; shell: root.shell; icon: ""; title: "Pick from screen"; detail: "Copies and saves the color"; onClicked: root.pick() }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    property bool loaded: false
    opensPopup: true
    css: "sudoku"; text: "󱇙"; tooltip: "Sudoku"
    active: root.shell.popupName === "sudoku"
    onClicked: { root.loaded = true; root.shell.togglePopup("sudoku") }
    Connections {
        target: root.shell
        function onPopupNameChanged() { if (root.popupEnabled && root.shell.popupName === "sudoku") root.loaded = true }
    }
    Loader {
        active: root.loaded; visible: false
        sourceComponent: Component { SudokuPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
}

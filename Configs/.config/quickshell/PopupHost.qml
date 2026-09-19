pragma ComponentBehavior: Bound
import QtQuick

// Popups opened by name (IPC, keybind, menutree) must exist even when the active
// layout carries no module to host them. One instance per bar; each entry stands
// down when its owning module is on the bar, so only one instance ever answers.
Item {
    id: root
    required property var shell
    required property Item anchorItem
    required property bool popupsAllowed

    component Host: Loader {
        id: host
        required property string popup
        required property string owner
        property bool everOpened: false
        active: host.everOpened && !root.shell.barModules.includes(host.owner)
        visible: false
        Connections {
            target: root.shell
            function onPopupNameChanged() {
                if (root.popupsAllowed && root.shell.popupName === host.popup) host.everOpened = true
            }
        }
    }

    Host {
        popup: "sudoku"; owner: "sudoku"
        sourceComponent: Component { SudokuPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "cliphist"; owner: "capture"
        sourceComponent: Component { CliphistPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "bookmarks"; owner: "menu"
        sourceComponent: Component { Bookmarks { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
}

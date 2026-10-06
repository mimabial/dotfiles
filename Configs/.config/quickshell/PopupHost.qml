pragma ComponentBehavior: Bound
import QtQuick

// Popups opened by name (IPC, keybind, menutree) must exist even when the active
// layout carries no module to host them. One instance per bar.
Item {
    id: root
    required property var shell
    required property Item anchorItem
    required property bool popupsAllowed

    component Host: LazyPopup { shell: root.shell; popupsAllowed: root.popupsAllowed }

    Host {
        popup: "sudoku"; owners: ["sudoku"]
        sourceComponent: Component { SudokuPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "cliphist"; owners: ["capture"]
        sourceComponent: Component { CliphistPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "bitwarden"; owners: ["bitwarden"]
        sourceComponent: Component { BitwardenPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "spotlight"; owners: ["menu"]
        sourceComponent: Component { StartPopup { popupName: "spotlight"; anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    Host {
        popup: "bookmarks"; owners: ["menu"]
        sourceComponent: Component { Bookmarks { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
}

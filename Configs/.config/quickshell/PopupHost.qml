pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var shell
    required property Item anchorItem
    required property bool popupEnabled

    component Host: LazyPopup { shell: root.shell; popupEnabled: root.popupEnabled }

    Host {
        popupName: "desktop"; owners: ["barlayout", "windowlayout", "gnome-quick-settings"]
        sourceComponent: Component { DesktopPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "sudoku"; owners: ["sudoku"]
        sourceComponent: Component { SudokuPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "cliphist"; owners: ["capture"]
        sourceComponent: Component { CliphistPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "bitwarden"; owners: ["bitwarden"]
        sourceComponent: Component { BitwardenPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "spotlight"; sharedWith: ["start"]; owners: ["menu"]
        sourceComponent: Component { StartPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "windowinfo"; owners: []
        sourceComponent: Component { WindowInfoPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "updates"; owners: ["updates"]
        sourceComponent: Component { UpdatesPopup { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
    Host {
        popupName: "bookmarks"; owners: ["menu"]
        sourceComponent: Component { Bookmarks { anchorItem: root.anchorItem; shell: root.shell; popupEnabled: root.popupEnabled } }
    }
}

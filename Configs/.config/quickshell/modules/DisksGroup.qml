pragma ComponentBehavior: Bound

import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showPrinters: false
    property bool printersFirst: false
    property bool showWhenIdle: false
    css: "disks"; reverse: true; secondaryAvailable: root.showPrinters
    holdOpen: ["disks", "printers"].includes(root.shell.popupName)
    slots: !root.showPrinters ? [disksSlot]
        : root.printersFirst ? [printersSlot, disksSlot] : [disksSlot, printersSlot]

    Component { id: disksSlot; BarButton {
        id: disksButton
        shell: root.shell; css: "removable"
        text: Removable.barGlyph
        readonly property bool shown: Removable.present || root.showWhenIdle
        visible: shown
        active: Removable.anyBusy
        onClicked: button => button === Qt.RightButton ? Removable.rescan()
            : button === Qt.MiddleButton ? Removable.openFirstMounted()
            : root.shell.togglePopup("disks")
        DisksPopup { anchorItem: disksButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: printersSlot; PrintersButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}

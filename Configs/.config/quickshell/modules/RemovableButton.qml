pragma ComponentBehavior: Bound

import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool showBadge: false
    css: "removable"
    visible: Removable.store.alwaysShow !== false || Removable.present
    text: Removable.barGlyph
    badgeText: showBadge && Removable.deviceCount ? countGlyph(Removable.deviceCount) : ""
    active: Removable.anyBusy
    onClicked: button => button === Qt.RightButton ? Removable.rescan()
        : button === Qt.MiddleButton ? Removable.openFirstMounted()
        : root.shell.togglePopup("disks")
    DisksPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

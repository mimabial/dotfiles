pragma ComponentBehavior: Bound
import QtQuick
import qs as Bar

Bar.BarButton {
    id: root
    property bool popupsAllowed: true
    readonly property var service: shell.quickshare
    css: "quickshare"
    text: "󰒗"
    tooltip: "Quick Share"
    active: service.discoverable || service.activeTransfers > 0
    badgeText: service.requests ? countText(service.requests) : ""
    onClicked: root.shell.togglePopup("quickshare")
    QuickSharePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

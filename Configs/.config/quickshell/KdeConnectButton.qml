pragma ComponentBehavior: Bound
import QtQuick
import qs as Bar

Bar.BarButton {
    id: root
    property bool popupsAllowed: true
    property bool showBadge: true
    readonly property int deviceCount: root.shell.kdeconnect.reachableDevices.count
    css: "kdeconnect"
    text: "󰒗"
    tooltip: "KDE Connect"
    badgeText: showBadge && deviceCount ? root.countText(deviceCount) : ""
    onClicked: root.shell.togglePopup("kdeconnect")
    Bar.KdeConnectPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

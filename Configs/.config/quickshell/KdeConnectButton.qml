pragma ComponentBehavior: Bound
import QtQuick
import qs as Bar

Bar.BarButton {
    id: root
    required property Bar.KdeConnect service
    property bool popupEnabled: true
    property bool showBadge: false
    readonly property int deviceCount: root.service.deviceCount
    css: "kdeconnect"
    text: "󰒗"
    tooltip: "KDE Connect"
    badgeText: showBadge && deviceCount ? root.countText(deviceCount) : ""
    onClicked: root.shell.togglePopup("kdeconnect")
    Bar.KdeConnectPopup { service: root.service; anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

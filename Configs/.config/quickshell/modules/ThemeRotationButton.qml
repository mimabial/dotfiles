import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    readonly property var themeRotation: shell.themeRotation
    css: "themerotation"
    text: "󰏘"
    badgeText: themeRotation.enabled ? "󰑖" : ""
    tooltip: themeRotation.statusText
    active: root.shell.popupName === "themerotation"

    onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("themerotation")
        : button === Qt.RightButton ? themeRotation.setEnabled(!themeRotation.enabled)
        : themeRotation.rotate()

    ThemeRotationPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

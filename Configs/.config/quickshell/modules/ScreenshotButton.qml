import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "screenshot"; text: "󰄄"
    tooltip: "<b>Screenshot</b>\nLeft: Panel\nMiddle: Full screen\nRight: Focused monitor"
    // the old three-way click stays; left opens the panel
    onClicked: button => button === Qt.MiddleButton
        ? root.shell.run(["hyprshell", "screenshot", "p"])
        : button === Qt.RightButton
            ? root.shell.run(["hyprshell", "screenshot", "m"])
            : root.shell.togglePopup("screenshot")
    ScreenshotPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

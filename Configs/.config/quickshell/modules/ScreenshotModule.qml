import QtQuick
import QtQuick.Layouts
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-screenshot"; text: "󰄄"
    // the old three-way click stays; left opens the panel
    onClicked: button => button === Qt.MiddleButton
        ? root.shell.run(["hyprshell", "screenshot", "p"])
        : button === Qt.RightButton
            ? root.shell.run(["hyprshell", "screenshot", "m"])
            : root.shell.togglePopup("screenshot")
    ScreenshotPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

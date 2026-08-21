import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showDate: false
    shell: root.shell; css: "datetime"; Layout.fillWidth: true
    // the main bar reads the date off the clock popup; the left bar has
    // the room to keep it on the drawer
    primary: Component { ClockButton {
        shell: root.shell; kind: "main"; css: "clock.time"; fontWeight: Font.Bold
        timerPopup: root.shell.layoutName === "main"; popupEnabled: root.popupsAllowed
    } }
    secondaryAvailable: root.showDate
    secondary: Component { BarButton {
        shell: root.shell; css: "clock.date"; fontWeight: Font.Bold
        text: Qt.formatDate(root.shell.clock.date, "ddd\ndd\nMMM")
    } }
}

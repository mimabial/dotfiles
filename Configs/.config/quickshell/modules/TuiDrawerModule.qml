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
    shell: root.shell; css: "tui-drawer"; Layout.fillWidth: true
    primary: Component { BarButton {
        shell: root.shell; css: "custom-terminal"; text: ""; textColor: root.shell.role("c9", root.shell.foreground)
        onClicked: root.shell.run(["kitty"])
    } }

}

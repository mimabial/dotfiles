import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-dmark"; text: "—"; fontWeight: Font.Bold
    textColor: root.shell.role("c7", root.shell.foreground)
}

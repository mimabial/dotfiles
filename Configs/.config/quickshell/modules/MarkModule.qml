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
    shell: root.shell; css: "mark"; reverse: true; Layout.fillWidth: true
    readonly property bool shown: root.shell.workflow === "gaming"
    visible: root.shown
    holdOpen: root.shell.popupName === "cliphist"
    primary: Component { BarButton { shell: root.shell; css: "custom-mark"; text: "—"; fontWeight: Font.Bold; textColor: root.shell.role("c7", root.shell.foreground) } }
    secondary: Component { ColumnLayout { spacing: 0;
        BarButton { Layout.fillWidth: true; readonly property bool shown: root.shell.workflow === "gaming"
    visible: root.shown; shell: root.shell; text: ""; tooltip: "GameMode active" }
    } }
}

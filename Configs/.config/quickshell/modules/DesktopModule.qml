import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property int layoutRevision: 0
    shell: root.shell; css: "desktop"; Layout.fillWidth: true
    holdOpen: root.shell.popupName === "desktop"
    property FileView layoutState: FileView { path: root.shell.home + "/.local/state/hypr/window-layout.lua"; watchChanges: true; printErrors: false; onLoaded: ++root.layoutRevision; onFileChanged: reload() }
    primary: Component { ScriptButton {
        id: layoutButton
        shell: root.shell; css: "custom-window-layout"; command: ["hyprshell", "util/window-layout", "--waybar"]; interval: 86400000; refreshKey: root.layoutRevision
        tooltip: output.tooltip + "\nLeft: options · Middle/right: next/previous"
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("desktop") : root.shell.run(["hyprshell", "util/window-layout", button === Qt.RightButton ? "--toggle-reverse" : "--toggle"])
        DesktopPopup { anchorItem: layoutButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { ScriptButton { Layout.fillWidth: true; shell: root.shell; css: "custom-workflows"; command: ["hyprshell", "util/workflows", "--waybar"]; interval: 86400000; refreshKey: root.shell.workflow; onClicked: root.shell.togglePopup("desktop") } }
}

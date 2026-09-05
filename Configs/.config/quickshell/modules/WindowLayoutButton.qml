import QtQuick
import Quickshell.Io
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    property int revision: 0
    css: "window-layout"; tooltip: ""; command: ["hyprshell", "util/window-layout", "--bar"]; interval: 86400000; refreshKey: revision
    onClicked: button => button === Qt.LeftButton ? shell.togglePopup("desktop") : shell.run(["hyprshell", "util/window-layout", button === Qt.RightButton ? "--toggle-reverse" : "--toggle"])
    property FileView stateFile: FileView { path: root.shell.home + "/.local/state/hypr/window-layout.lua"; watchChanges: true; printErrors: false; onLoaded: ++root.revision; onFileChanged: reload() }
    DesktopPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

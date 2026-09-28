import QtQuick
import Quickshell.Io
import "modules"
import "StartMenuModel.js" as StartMenuModel

BarButton {
    id: root
    property bool popupEnabled: true
    property bool dropdown: false
    css: "menu"; text: shell.distroGlyph
    onHoveredChanged: if (hovered) shell.cycleDistroGlyph()
    onDropdownChanged: menuTree.running = dropdown
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "menutree"])
        : button === Qt.MiddleButton ? shell.run([shell.terminal]) : shell.togglePopup(dropdown ? "hyprmenu" : "start")
    StartPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    Bookmarks { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    MenuBarPopup {
        id: dropdownMenu
        property var menus: ({})
        items: StartMenuModel.dropdownItems(menus, target => root.shell.menuTargetActive(target))
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled && root.dropdown; popupName: "hyprmenu"
        onOpenChanged: if (open) root.shell.refreshMenuState(); else menuTree.running = true
        Process {
            id: menuTree
            command: ["hyprshell", "rofi/menutree", "--dump-json"]
            stdout: StdioCollector { waitForEnd: true; onStreamFinished: dropdownMenu.menus = JSON.parse(text) }
        }
    }
}

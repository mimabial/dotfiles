import QtQuick

BarButton {
    id: root
    property bool popupEnabled: true
    css: "hyprmenu"; text: shell.distroGlyph
    onHoveredChanged: if (hovered) shell.cycleDistroGlyph()
    onClicked: button => button === Qt.RightButton ? shell.run(["hyprshell", "menutree"])
        : button === Qt.MiddleButton ? shell.run([shell.terminal]) : shell.togglePopup("start")
    StartPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
    Bookmarks { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

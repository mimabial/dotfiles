import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "barlayout"; text: shell.barLayoutIcon(shell.layoutName)
    textColor: shell.store.barTransparent ? shell.accent : shell.foreground
    tooltip: "Bar: " + shell.layoutName + " · " + (shell.store.barTransparent ? "transparent" : "themed") + "\nLeft: layouts · Middle: next · Right: transparency"
    onClicked: button => button === Qt.LeftButton ? shell.togglePopup("barlayout") : button === Qt.RightButton ? shell.toggleBarTransparency() : shell.run(["hyprshell", "quickshell/layout", "next"])
    BarLayoutPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

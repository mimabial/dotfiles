import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "wallpaper"
    text: "󰸉"
    badgeText: Wallpaper.perWorkspace ? "󰝥" : Wallpaper.enabled ? "󰑖" : ""
    textColor: Wallpaper.lastError !== "" ? shell.role("error", shell.foreground) : shell.foreground
    tooltip: Wallpaper.perWorkspace ? Wallpaper.nextText() : Wallpaper.enabled ? "Automatic switching · " + Wallpaper.intervalLabel(Wallpaper.intervalMinutes) : "Automatic switching paused"
    active: root.shell.popupName === "wallpaper"

    onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("wallpaper")
        : button === Qt.RightButton ? Wallpaper.setEnabled(!Wallpaper.enabled)
        : Wallpaper.applyNext()
    onWheeled: delta => Wallpaper.applyAdjacent(delta > 0 ? 1 : -1)

    WallpaperPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "wallpaper"
    text: "󰸉"
    // accent means the rotation is running; plain foreground means it is paused
    textColor: Wallpaper.lastError !== "" ? shell.role("error", shell.foreground)
        : Wallpaper.enabled ? shell.accent : shell.foreground
    active: root.shell.popupName === "wallpaper"

    onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("wallpaper")
        : button === Qt.RightButton ? Wallpaper.setEnabled(!Wallpaper.enabled)
        : Wallpaper.applyNext()
    onWheeled: delta => {
        root.shell.run(["hyprshell", "wallpaper", delta > 0 ? "next" : "previous", "--global"])
        Wallpaper.nudge()
    }

    WallpaperPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

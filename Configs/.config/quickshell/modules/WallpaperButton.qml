import QtQuick
import ".."

// Auto-wallpaper button. The glyph carries accent while the rotation runs, so
// the bar shows automation state without a reading of its own.
BarButton {
    id: root
    property bool popupsAllowed: true
    css: "wallpaper"
    text: "󰸉"
    tooltip: "Switch wallpaper\nLeft: Panel\nMiddle: Next now\nRight: Pause or resume\nWheel: Step the theme's wallpapers"
    // accent means the rotation is running; plain foreground means it is paused
    textColor: Wallpaper.lastError !== "" ? shell.role("error", shell.foreground)
        : Wallpaper.enabled ? shell.accent : shell.foreground
    active: root.shell.popupName === "wallpaper"

    onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("wallpaper")
        : button === Qt.RightButton ? Wallpaper.setEnabled(!Wallpaper.enabled)
        : Wallpaper.applyNext()
    // steps the catalog through hyprshell, which the service re-anchors onto
    onWheeled: delta => {
        root.shell.run(["hyprshell", "wallpaper", delta > 0 ? "next" : "previous", "--global"])
        Wallpaper.nudge()
    }

    WallpaperPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

import QtQuick
import ".."

// Auto-wallpaper button. The glyph carries accent while the rotation runs, so
// the bar shows automation state without a reading of its own. A button that owns a
// popup never tooltips (BarButton suppresses it once anchored), so the click
// map is documented here rather than in a tooltip that cannot appear:
//   left   open the wallpaper panel
//   middle apply the next wallpaper now, per the configured rotation
//   right  pause or resume automatic switching
//   wheel  step the theme's wallpapers directly, either way
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
    // steps the catalog through hyprshell, which the service re-anchors onto
    onWheeled: delta => {
        root.shell.run(["hyprshell", "wallpaper", delta > 0 ? "next" : "previous", "--global"])
        Wallpaper.nudge()
    }

    WallpaperPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

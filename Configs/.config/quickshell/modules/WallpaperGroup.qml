import QtQuick
import QtQuick.Layouts
import ".."

// appearance drawer: the wallpaper button heads it, the rest of the look-and-feel
// controls sit behind it. Slot order is bottom-up when reverse is set, so the
// array reads in reverse of what the bar shows.
BarGroup {
    id: root
    property bool popupsAllowed: true
    shell: root.shell; css: "wallpaper-group"; Layout.fillWidth: true
    holdOpen: ["wallpaper", "colormode", "colorpicker", "barlayout", "desktop"].includes(root.shell.popupName)
    slots: [wallpaperSlot, colorModeSlot, barLayoutSlot, desktopSlot]

    // window layout and workflow share one framed box; both target the desktop popup
    Component { id: desktopSlot; BarGroup {
        shell: root.shell; css: "desktop-group"; alwaysOpen: true; Layout.fillWidth: true
        slots: [windowLayoutSlot, workflowsSlot]
    } }

    Component { id: wallpaperSlot; WallpaperButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: colorModeSlot; ScriptButton {
        id: colorButton; shell: root.shell; css: "colormode"
        command: ["hyprshell", "waybar/waybar.colormode"]; interval: 86400000; refreshKey: root.shell.palette
        onClicked: button => button === Qt.LeftButton
            ? root.shell.togglePopup("colormode")
            : root.shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
        ColorModePopup { anchorItem: colorButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: barLayoutSlot; BarButton {
        id: barButton; shell: root.shell; css: "barlayout-button"; text: root.shell.barLayoutIcon(root.shell.layoutName)
        textColor: root.shell.store.barTransparent ? root.shell.accent : root.shell.foreground
        tooltip: "Bar: " + root.shell.layoutName + " · " + (root.shell.store.barTransparent ? "transparent" : "themed") + "\nLeft: layouts · Middle: next · Right: transparency"
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("barlayout")
            : button === Qt.RightButton ? root.shell.toggleBarTransparency()
            : root.shell.run(["hyprshell", "quickshell/layout", "next"])
        BarLayoutPopup { anchorItem: barButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: windowLayoutSlot; WindowLayoutButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: workflowsSlot; ScriptButton {
        shell: root.shell; css: "workflows"
        command: ["hyprshell", "util/workflows", "--waybar"]; interval: 86400000; refreshKey: root.shell.workflow
        onClicked: root.shell.togglePopup("desktop")
    } }
}

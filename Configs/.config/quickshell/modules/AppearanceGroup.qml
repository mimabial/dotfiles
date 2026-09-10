pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

// appearance drawer: the wallpaper button heads it, the rest of the look-and-feel
// controls sit behind it. Slot order is bottom-up when reverse is set, so the
// array reads in reverse of what the bar shows.
BarGroup {
    id: root
    property bool popupsAllowed: true
    shell: root.shell; css: "appearance-group"
    Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
    holdOpen: ["wallpaper", "colormode", "colorpicker", "barlayout", "desktop"].includes(root.shell.popupName)
    // BarGroup's `reverse` only flips a drawer while it grows; an always-open
    // group keeps array order, so flip the array itself
    readonly property var order: [wallpaperSlot, colorModeSlot, barLayoutSlot, desktopSlot]
    slots: root.reverse && root.alwaysOpen ? root.order.slice().reverse() : root.order

    // window layout and workflow share one framed box; both target the desktop popup
    Component { id: desktopSlot; BarGroup {
        shell: root.shell; css: "desktop-group"; alwaysOpen: true; vertical: root.vertical
        Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
        slots: [windowLayoutSlot, workflowsSlot]
    } }

    Component { id: wallpaperSlot; WallpaperButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: colorModeSlot; ScriptButton {
        id: colorButton; shell: root.shell; css: "colormode"; tooltip: ""
        command: ["hyprshell", "quickshell/color-mode"]; interval: 86400000; refreshKey: root.shell.palette
        onClicked: button => button === Qt.LeftButton
            ? root.shell.togglePopup("colormode")
            : root.shell.run(["hyprshell", "theme/color-mode", button === Qt.RightButton ? "-p" : "-n"])
        ColorModePopup { anchorItem: colorButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: barLayoutSlot; BarButton {
        id: barButton; shell: root.shell; css: "barlayout-button"; text: root.shell.barLayoutIcon()
        textColor: root.shell.store.barTransparent ? root.shell.accent : root.shell.foreground
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("barlayout")
            : button === Qt.RightButton ? root.shell.toggleBarTransparency()
            : root.shell.run(["hyprshell", "quickshell/layout", "next"])
        BarLayoutPopup { anchorItem: barButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: windowLayoutSlot; WindowLayoutButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: workflowsSlot; ScriptButton {
        shell: root.shell; css: "workflows"
        command: ["hyprshell", "util/workflows", "--bar"]; interval: 86400000; refreshKey: root.shell.workflow
        onClicked: root.shell.togglePopup("desktop")
    } }
}

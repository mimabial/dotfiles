pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showCliphist: true
    property bool showScreenshot: true
    property bool showPicker: false
    shell: root.shell; css: "capture"; Layout.fillWidth: true; radius: root.shell.moduleRadius
    secondaryAvailable: root.showCliphist || root.showScreenshot || root.showPicker
    holdOpen: ["screenrecord", "cliphist", "screenshot", "colorpicker"].includes(root.shell.popupName)
    slots: [recordSlot].concat(root.showCliphist ? [cliphistSlot] : [])
        .concat(root.showScreenshot ? [shotSlot] : []).concat(root.showPicker ? [pickerSlot] : [])

    // the panel is opened by keybind, so it cannot live in a slot the drawer
    // creates on hover — it would be born already open and never initialise
    CliphistPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }

    Component { id: recordSlot; ScreenRecordButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: cliphistSlot; BarButton {
        id: cliphistModule
        tooltip: " Clipboard history\nLeft: Panel\nMiddle: Image history\nRight: Favorites"
        shell: root.shell; css: "cliphist"; text: ""
        onClicked: button => button === Qt.MiddleButton
            ? root.shell.run(["hyprshell", "cliphist", "--image-history"])
            : button === Qt.RightButton
                ? root.shell.run(["hyprshell", "cliphist", "--favorites"])
                : root.shell.togglePopup("cliphist")
    } }
    Component { id: shotSlot; BarButton {
        id: shotModule
        tooltip: "<b>Screenshot</b>\nLeft: Panel\nMiddle: Full screen\nRight: Focused monitor"
        shell: root.shell; css: "screenshot"; text: "󰄄"
        // the old three-way click stays; left opens the panel
        onClicked: button => button === Qt.MiddleButton
            ? root.shell.run(["hyprshell", "screenshot", "p"])
            : button === Qt.RightButton
                ? root.shell.run(["hyprshell", "screenshot", "m"])
                : root.shell.togglePopup("screenshot")
        ScreenshotPopup { anchorItem: shotModule; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: pickerSlot; ColorPickerButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}

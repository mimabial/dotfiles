import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showCliphist: true
    property bool showScreenshot: true
    property bool showPicker: false
    shell: root.shell; css: "screen"; Layout.fillWidth: true; radius: root.shell.moduleRadius
    secondaryAvailable: root.showCliphist || root.showScreenshot || root.showPicker
    holdOpen: ["screenrecord", "cliphist", "screenshot", "colorpicker"].includes(root.shell.popupName)
    slots: [recordSlot].concat(root.showCliphist ? [cliphistSlot] : [])
        .concat(root.showScreenshot ? [shotSlot] : []).concat(root.showPicker ? [pickerSlot] : [])

    // the panel is opened by keybind, so it cannot live in a slot the drawer
    // creates on hover — it would be born already open and never initialise
    CliphistPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }

    Component { id: recordSlot; ScriptButton {
        id: recordButton
        shell: root.shell; css: "screenrecord"
        readonly property bool recording: output.class === "recording"
        fill: recording ? root.shell.alpha(root.shell.role("c9", root.shell.accent), blink.phase) : "transparent"
        textColor: recording
            ? (blink.phase > .5 ? root.shell.role("bg", root.shell.background) : root.shell.role("c9", root.shell.foreground))
            : root.shell.role("c1", root.shell.foreground)
        SequentialAnimation {
            id: blink
            property real phase: 0
            running: recordButton.recording; loops: Animation.Infinite
            onStopped: phase = 0
            NumberAnimation { target: blink; property: "phase"; from: 0; to: 1; duration: 500 }
            NumberAnimation { target: blink; property: "phase"; from: 1; to: 0; duration: 500 }
        }
        command: ["hyprshell", "screenrecord", "--status"]; interval: 1000
        // the panel replaces the portal's ScreenCast dialog
        onClicked: button => button === Qt.RightButton
            ? root.shell.run(["hyprshell", "screenrecord", "--quit"])
            : root.shell.togglePopup("screenrecord")
        ScreenRecordPopup { anchorItem: recordButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    Component { id: cliphistSlot; BarButton {
        id: cliphistModule
        shell: root.shell; css: "cliphist"; text: ""
        onClicked: button => button === Qt.MiddleButton
            ? root.shell.run(["hyprshell", "cliphist", "--image-history"])
            : button === Qt.RightButton
                ? root.shell.run(["hyprshell", "cliphist", "--favorites"])
                : root.shell.togglePopup("cliphist")
    } }
    Component { id: shotSlot; BarButton {
        id: shotModule
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

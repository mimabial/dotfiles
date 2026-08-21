import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Wayland
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showCliphist: true
    property bool showScreenshot: true
    shell: root.shell; css: "screen"; Layout.fillWidth: true; radius: root.shell.moduleRadius
    secondaryAvailable: root.showCliphist || root.showScreenshot
    holdOpen: ["screenrecord", "cliphist", "screenshot"].includes(root.shell.popupName)
    primary: Component { ScriptButton {
        id: recordButton
        shell: root.shell; css: "custom-screenrecord"
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
    secondary: Component { ColumnLayout { spacing: 0
        BarButton {
            id: cliphistModule
            Layout.fillWidth: true; visible: root.showCliphist
            shell: root.shell; css: "custom-cliphist"; text: ""
            onClicked: button => button === Qt.MiddleButton
                ? root.shell.run(["hyprshell", "cliphist", "--image-history"])
                : button === Qt.RightButton
                    ? root.shell.run(["hyprshell", "cliphist", "--favorites"])
                    : root.shell.togglePopup("cliphist")
            CliphistPopup { anchorItem: cliphistModule; shell: root.shell; popupEnabled: root.popupsAllowed }
        }
        BarButton {
            id: shotModule
            Layout.fillWidth: true; visible: root.showScreenshot; shell: root.shell; css: "custom-screenshot"; text: "󰄄"
            // the old three-way click stays; left opens the panel
            onClicked: button => button === Qt.MiddleButton
                ? root.shell.run(["hyprshell", "screenshot", "p"])
                : button === Qt.RightButton
                    ? root.shell.run(["hyprshell", "screenshot", "m"])
                    : root.shell.togglePopup("screenshot")
            ScreenshotPopup { anchorItem: shotModule; shell: root.shell; popupEnabled: root.popupsAllowed }
        }
    } }
}

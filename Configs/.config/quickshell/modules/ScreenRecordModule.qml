import QtQuick
import QtQuick.Layouts
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-screenrecord"
    readonly property bool recording: output.class === "recording"
    fill: recording ? root.shell.alpha(root.shell.role("c9", root.shell.accent), blink.phase) : "transparent"
    textColor: recording
        ? (blink.phase > .5 ? root.shell.role("bg", root.shell.background) : root.shell.role("c9", root.shell.foreground))
        : root.shell.role("c1", root.shell.foreground)
    SequentialAnimation {
        id: blink
        property real phase: 0
        running: root.recording; loops: Animation.Infinite
        onStopped: phase = 0
        NumberAnimation { target: blink; property: "phase"; from: 0; to: 1; duration: 500 }
        NumberAnimation { target: blink; property: "phase"; from: 1; to: 0; duration: 500 }
    }
    command: ["hyprshell", "screenrecord", "--status"]; interval: 1000
    // the panel replaces the portal's ScreenCast dialog
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "screenrecord", "--quit"])
        : root.shell.togglePopup("screenrecord")
    ScreenRecordPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

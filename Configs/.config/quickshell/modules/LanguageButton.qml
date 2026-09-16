import QtQuick
import Quickshell.Hyprland
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    readonly property var layouts: String(output.layouts || "").split(",").map(entry => entry.trim()).filter(entry => entry !== "")
    readonly property bool shown: raw !== ""
    css: "language"
    command: ["hyprshell", "util/keyboard-layout"]
    polling: false
    Component.onCompleted: refresh()
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("language")
        root.shell.run(["hyprshell", "util/keyboard-switch.sh"], root.refresh)
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event || !event.name) return
            const name = String(event.name)
            if (name.indexOf("activelayout") !== -1 || name === "configreloaded") root.refresh()
        }
    }
    Timer {
        interval: 10000
        running: root.raw === ""
        repeat: true
        onTriggered: root.refresh()
    }
    LanguagePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}

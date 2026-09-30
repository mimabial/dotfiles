pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    readonly property string script: Quickshell.env("HOME") + "/.local/lib/hypr/system/monitor-mirror.sh"
    function toggle() { Quickshell.execDetached([root.script, "toggle"]) }
    Process { id: statusProbe; running: true; command: [root.script, "status"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.active = text.trim() === "on" } }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded" || event.name.startsWith("monitor")) statusProbe.running = true }
    }
}

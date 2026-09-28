import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland already streams submap changes into this process, so the module binds
// to the event instead of a provider poll. It is only on screen while a submap is
// held; the blink is what makes that state hard to miss.
BarButton {
    id: root
    property color baseColor: shell.foreground
    property bool alt: false
    property string submap: ""
    property bool queryPending: false
    property int eventSerial: 0
    property int querySerial: 0
    property real blinkPhase: 1
    function updateSubmap(value) {
        const name = String(value).trim()
        submap = name === "default" || name === "reset" ? "" : name
        console.log("submap resolved", JSON.stringify(submap))
    }
    function refreshSubmap() {
        if (submapQuery.running) queryPending = true
        else {
            querySerial = eventSerial
            submapQuery.running = true
        }
    }

    css: "submap"
    visible: submap !== ""
    text: alt ? " " + submap : "󰇘"
    tooltip: "submap: " + submap
    smoothTextColor: false
    textColor: shell.alpha(baseColor, .2 + (baseColor.a - .2) * blinkPhase)

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "submap") return
            console.log("submap event", JSON.stringify(event.data))
            root.eventSerial++
            if (String(event.data).trim()) root.updateSubmap(event.data)
            else root.refreshSubmap()
        }
    }
    // An empty event can arrive during a theme cycle while the submap is still active.
    Process {
        id: submapQuery
        command: ["hyprctl", "submap"]
        stdout: SplitParser {
            onRead: line => {
                console.log("submap query", JSON.stringify(line), root.queryPending, root.querySerial, root.eventSerial)
                if (line.trim() && !root.queryPending && root.querySerial === root.eventSerial)
                    root.updateSubmap(line)
            }
        }
        onRunningChanged: if (!running && root.queryPending) {
            root.queryPending = false
            root.refreshSubmap()
        }
    }
    Component.onCompleted: refreshSubmap()

    SequentialAnimation on blinkPhase {
        running: root.visible
        loops: Animation.Infinite
        onStopped: root.blinkPhase = 1
        NumberAnimation { from: 1; to: 0; duration: 550; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0; to: 1; duration: 550; easing.type: Easing.InOutQuad }
    }
}

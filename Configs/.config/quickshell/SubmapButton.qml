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
    function updateSubmap(value) { const name = String(value).trim(); submap = name === "default" ? "" : name }

    css: "submap"
    visible: submap !== ""
    text: alt ? " " + submap : "󰇘"
    tooltip: "submap: " + submap
    // the hover fade would fight the animation for the same property
    smoothTextColor: false
    textColor: baseColor

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "submap") root.updateSubmap(event.data) }
    }
    // nothing replays the event, so a bar started inside a submap needs one read
    Process {
        running: true
        command: ["hyprctl", "submap"]
        stdout: SplitParser { onRead: line => root.updateSubmap(line) }
    }

    SequentialAnimation on textColor {
        running: root.visible
        loops: Animation.Infinite
        ColorAnimation { to: root.shell.alpha(root.baseColor, .2); duration: 550; easing.type: Easing.InOutQuad }
        ColorAnimation { to: root.baseColor; duration: 550; easing.type: Easing.InOutQuad }
    }
}

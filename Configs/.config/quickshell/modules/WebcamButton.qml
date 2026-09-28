import QtQuick
import Quickshell.Io
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool inUse: false
    property bool recheckPending: false
    css: "webcam"
    text: "\u{f05a0}"
    smoothTextColor: false
    textColor: inUse ? shell.alpha(shell.role("error", shell.foreground), .25 + blink.phase * .75) : shell.foreground
    onClicked: shell.togglePopup("webcam")

    SequentialAnimation {
        id: blink
        property real phase: 0
        running: root.inUse; loops: Animation.Infinite
        NumberAnimation { target: blink; property: "phase"; from: 0; to: 1; duration: 600 }
        NumberAnimation { target: blink; property: "phase"; from: 1; to: 0; duration: 600 }
    }

    function checkHolders() {
        if (holders.running) recheckPending = true
        else holders.running = true
    }

    // a reload kills only the direct child, so each command is exec'd instead of piped;
    // inotifywait's own "Watches established." line triggers the first check, so no open slips in before the watch
    Process {
        running: true
        command: ["sh", "-c", "exec inotifywait -m -e open,close /dev/video* 2>&1"]
        stdout: SplitParser { onRead: root.checkHolders() }
    }
    Process {
        id: holders
        command: ["sh", "-c", "exec fuser -s /dev/video*"]
        onExited: code => {
            root.inUse = code === 0
            if (root.recheckPending) { root.recheckPending = false; Qt.callLater(root.checkHolders) }
        }
    }

    PopupCard {
        id: card
        anchorItem: root; shell: root.shell; popupName: "webcam"; popupEnabled: root.popupsAllowed
        contentWidth: Style.px(420)
        // loading by URL keeps QtMultimedia out of the bar process until the popup opens
        Loader {
            width: parent.width
            active: card.visible
            Component.onCompleted: setSource(Qt.resolvedUrl("../WebcamPanel.qml"), {shell: root.shell, card: card})
        }
    }
}

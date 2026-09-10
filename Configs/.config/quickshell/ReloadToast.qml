import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var shell
    property bool shown: false
    property bool failed: false
    property string detail: ""
    readonly property string title: root.failed ? "Configuration reload failed" : "Configuration reloaded"

    // Quickshell hands over the whole trace, headed by a generic line the toast
    // already says itself. What is left are the "caused by" frames, innermost
    // last, and that is the one carrying the file and line worth reading.
    function showFailure(error) {
        const lines = String(error).split("\n").map(line => line.trim())
            .filter(line => line.length > 0 && line !== "Failed to load configuration")
        root.detail = lines.slice(0, 4).join("\n")
        root.failed = true
        root.show()
    }

    function showSuccess() {
        root.detail = ""
        root.failed = false
        root.show()
    }

    function show() { root.shown = true; hide.restart() }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); root.showSuccess() }
        function onReloadFailed(error: string) { Quickshell.inhibitReloadPopup(); root.showFailure(error) }
    }
    Timer { id: hide; interval: root.failed ? 8000 : 1400; onTriggered: root.shown = false }

    // The failure box is sized to hold a wrapped trace; the success line is one
    // short string, so it keeps measuring itself the way every other toast does.
    TextMetrics { id: titleMetrics; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; text: root.title }

    PanelWindow {
        id: win
        visible: root.shown
        anchors.top: root.shell.barEdge !== "top"; anchors.bottom: root.shell.barEdge === "top"
        margins.top: Style.xxxl; margins.bottom: Style.xxxl
        implicitWidth: root.failed
            ? Math.min(Style.px(520), win.screen ? Math.round(win.screen.width * 0.5) : Style.px(520))
            : titleMetrics.width + Style.xxl * 2
        implicitHeight: Math.max(34, content.implicitHeight + Style.lg * 2)
        color: "transparent"; exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hypr-shell-reload"; WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            anchors.fill: parent; radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .96)
            border.width: 1
            border.color: root.shell.alpha(root.shell.role(root.failed ? "error" : "act_br", root.shell.accent), .65)
            Column {
                id: content
                anchors.centerIn: parent
                width: parent.width - Style.xxl * 2
                spacing: Style.xs
                Text {
                    width: parent.width; elide: Text.ElideRight
                    horizontalAlignment: root.failed ? Text.AlignLeft : Text.AlignHCenter
                    text: root.title
                    color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Text {
                    width: parent.width; visible: root.detail.length > 0
                    textFormat: Text.PlainText; wrapMode: Text.WordWrap
                    maximumLineCount: 4; elide: Text.ElideRight
                    text: root.detail
                    color: root.shell.alpha(root.shell.foreground, .7)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.shown = false }
        }
    }
}

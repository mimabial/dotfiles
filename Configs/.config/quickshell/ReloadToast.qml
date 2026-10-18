pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var shell
    property bool shown: false
    property bool failed: false
    readonly property int failureShownMs: 8000
    readonly property int successShownMs: 1400
    property string detail: ""
    readonly property string title: root.failed ? "Configuration reload failed" : "Configuration reloaded"

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

    function show() { root.shown = true; toastExpiryTimer.restart() }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); root.showSuccess() }
        function onReloadFailed(error: string) { Quickshell.inhibitReloadPopup(); root.showFailure(error) }
    }
    Timer { id: toastExpiryTimer; interval: root.failed ? root.failureShownMs : root.successShownMs; onTriggered: root.shown = false }

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
            color: root.shell.alpha(Style.popupTinted(root.shell.role("alt_bg", root.shell.background)), Style.popupSurfaceOpacity)
            border.width: 1
            border.color: root.shell.alpha(root.failed ? root.shell.role("error", root.shell.accent) : Style.popupBorder(root.shell.role("act_br", root.shell.accent)), .65)
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

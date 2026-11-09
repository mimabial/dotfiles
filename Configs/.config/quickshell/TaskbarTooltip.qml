pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui
import "dock" as Dock

PopupWindow {
    id: root
    required property Item anchorItem
    required property var shell
    required property string appName
    required property var windows
    required property var windowFocused
    required property var windowParked
    required property var windowLabel
    property string suffix: ""
    property bool hovered: false
    property bool blocked: false
    property bool ready: false
    property bool advanced: true
    property bool showPreview: false
    property int delay: 450
    property int selectedIndex: -1
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property string edge: shell.barEdge

    function updateVisibility() {
        ready = false
        if (hovered && !blocked && appName !== "") hoverDwellTimer.restart()
        else hoverDwellTimer.stop()
    }
    function showNow() {
        if (hovered && !blocked && appName !== "") { hoverDwellTimer.stop(); ready = true }
    }
    onHoveredChanged: updateVisibility()
    onBlockedChanged: updateVisibility()
    onAppNameChanged: updateVisibility()
    visible: ready && hovered && !blocked && appName !== ""
    color: "transparent"
    implicitWidth: Math.ceil(bubble.width) + 1
    implicitHeight: Math.ceil(bubble.height) + 1

    Timer { id: hoverDwellTimer; interval: root.delay; onTriggered: root.ready = true }
    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1; rect.height: 1
        onAnchoring: {
            if (!root.anchorWindow || !root.anchorItem) return
            let x = root.anchorItem.width / 2 - root.width / 2
            let y = root.anchorItem.height + Commons.Style.gapsOut
            if (root.edge === "bottom") y = -root.height - Commons.Style.gapsOut
            else if (root.edge === "left") {
                x = root.anchorItem.width + Commons.Style.gapsOut
                y = root.anchorItem.height / 2 - root.height / 2
            }
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, x, y)
            anchor.rect.x = Math.round(point.x)
            anchor.rect.y = Math.round(point.y)
        }
    }
    BorderSurface {
        id: bubble
        color: Commons.Util.scaleAlpha(Commons.Style.popupTinted(Commons.Color.tooltip.background), Commons.Style.popupSurfaceOpacity)
        radius: Commons.Style.cornerRadius
        padding: Commons.Style.spacing.popupPadding
        width: content.implicitWidth + contentLeftInset + contentRightInset
        height: content.implicitHeight + contentTopInset + contentBottomInset
        Dock.AppTooltipContent {
            id: content
            x: parent.contentLeftInset
            y: parent.contentTopInset
            appName: root.appName
            suffix: root.suffix
            windows: root.windows
            advanced: root.advanced
            selectedIndex: root.selectedIndex
            windowFocused: root.windowFocused
            windowParked: root.windowParked
            windowLabel: root.windowLabel
            previews: root.showPreview && root.visible
            previewWidth: {
                const count = Math.max(1, root.windows.length)
                const available = root.anchorWindow?.screen?.width ?? Commons.Style.spacing.dropdownWidth
                return Math.min(Commons.Style.spacing.dropdownWidth, Math.max(0,
                    (available - bubble.contentLeftInset - bubble.contentRightInset
                        - (count + 1) * Commons.Style.spacing.sm) / count))
            }
        }
    }
}

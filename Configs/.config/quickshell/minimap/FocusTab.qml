pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs

PopupWindow {
    id: tip
    required property var shell
    required property Item host
    property Item target: null
    property string title: ""
    property string appClass: ""
    property string iconSource: ""
    property bool highlighted: false
    property string shownTitle: ""
    property string shownClass: ""
    property string shownIconSource: ""
    property bool animatePosition: false
    readonly property bool wanted: target !== null && title !== ""
    readonly property bool bottom: shell.barEdge === "bottom"
    readonly property real pad: Style.md
    readonly property real gap: Style.popupGap
    readonly property real travel: Style.px(760)
    readonly property real maxPillWidth: Style.px(560)
    readonly property real springK: 12.8
    readonly property real springD: 0.68
    readonly property real fadeLead: 2.2
    readonly property var window: host.QsWindow.window

    anchor {
        window: tip.window
        adjustment: PopupAdjustment.None
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1
    }
    visible: window !== null
    color: "transparent"
    implicitWidth: travel
    implicitHeight: pill.height + pad + gap
    mask: Region { item: pill.visible ? pill : null }

    function clamp(value, low, high) { return Math.max(low, Math.min(value, Math.max(low, high))) }
    function place() {
        if (!window || !target) return
        const origin = window.contentItem.mapFromItem(host, 0, 0)
        const center = window.contentItem.mapFromItem(target, target.width / 2, target.height / 2)
        const left = clamp(origin.x - Style.xxl, Style.sm, window.width - travel - Style.sm)
        anchor.rect.x = Math.round(left)
        anchor.rect.y = Math.round(bottom ? -implicitHeight : window.height)
        pill.targetX = clamp(center.x - left - pill.targetWidth / 2, 0, travel - pill.targetWidth)
        pill.targetY = bottom ? pad : gap
    }
    onTitleChanged: if (title) { shownTitle = title; shownClass = appClass; shownIconSource = iconSource }
    onAppClassChanged: if (title) shownClass = appClass
    onIconSourceChanged: if (title) shownIconSource = iconSource
    onTargetChanged: if (wanted) place()
    onWantedChanged: {
        if (!wanted) return
        if (pill.presence < 0.05) {
            animatePosition = false
            place()
            Qt.callLater(() => tip.animatePosition = true)
        } else place()
    }

    Rectangle {
        id: pill
        property real targetX: 0
        property real targetY: 0
        property real presence: tip.wanted ? 1 : 0
        readonly property real targetWidth: Math.min(tip.maxPillWidth, metrics.width + iconBox.width + Style.px(40))
        readonly property real lift: (1 - presence) * (tip.bottom ? 1 : -1) * (height + tip.gap)
        x: targetX
        y: targetY + lift
        width: targetWidth
        height: label.implicitHeight + Style.px(18)
        radius: Math.min(tip.shell.rounding, height / 2)
        color: tip.shell.alpha(tip.shell.barColor, Style.popupSurfaceOpacity)
        opacity: Math.max(0, Math.min(1, presence * tip.fadeLead))
        visible: opacity > 0
        MotionBehavior on presence { SpringAnimation { spring: tip.springK; damping: tip.springD; epsilon: MinimapState.progressEpsilon } }
        MotionBehavior on x { enabled: !Style.reduceMotion && tip.animatePosition; SpringAnimation { spring: tip.springK; damping: tip.springD; epsilon: 0.3 } }
        MotionBehavior on width { enabled: !Style.reduceMotion && tip.animatePosition; SpringAnimation { spring: tip.springK; damping: tip.springD; epsilon: 0.3 } }

        TextMetrics { id: metrics; text: tip.shownTitle; font.family: tip.shell.fontFamily; font.pixelSize: Style.body }
        Item {
            id: iconBox
            anchors.left: parent.left
            anchors.leftMargin: Style.xxl
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(label.implicitHeight * 1.2)
            height: width
            Image {
                id: icon
                anchors.fill: parent
                source: tip.shownIconSource
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: icon.status !== Image.Ready
                text: tip.shownClass ? tip.shownClass.charAt(0).toUpperCase() : "•"
                textFormat: Text.PlainText
                color: tip.highlighted ? tip.shell.accent : tip.shell.mutedText
                font.family: tip.shell.fontFamily
                font.pixelSize: Style.body
                font.bold: true
            }
        }
        Text {
            id: label
            anchors.left: iconBox.right
            anchors.leftMargin: Style.xl
            anchors.right: parent.right
            anchors.rightMargin: Style.xxxl
            anchors.verticalCenter: parent.verticalCenter
            text: tip.shownTitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: tip.shell.foreground
            font.family: tip.shell.fontFamily
            font.pixelSize: Style.body
        }
    }
}

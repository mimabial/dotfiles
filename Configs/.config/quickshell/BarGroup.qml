pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    property Component primary
    property Component secondary
    property var slots: []
    readonly property var slotComponents: slots.length ? slots : [primary, secondary].filter(c => c)
    readonly property var drawerSlots: slotComponents.slice(1)
    property bool reverse: false
    property bool holdOpen: false
    property bool alwaysOpen: false
    property bool secondaryAvailable: true
    property bool preload: false
    property real radius: shell.moduleRadius
    property color backgroundColor: root.boxColor("backgroundColor")
    property color borderColor: root.boxColor("borderColor")
    property color hoverBorderColor: {
        const spec = box.hover && "borderColor" in box.hover ? box.hover.borderColor : ["hvr_br", Style.hoverBorderAlpha]
        return !spec ? "transparent" : Array.isArray(spec) ? shell.alpha(shell.role(spec[0], borderColor), spec[1] ?? 1) : shell.role(spec, borderColor)
    }
    readonly property bool hovered: hover.hovered
    readonly property bool primaryFilled: hasVisibleContent(primaryLoader.item)
    readonly property bool drawersBeforePrimary: reverse && !alwaysOpen
    readonly property bool empty: alwaysOpen ? content.implicitHeight <= 0 && content.implicitWidth <= 0 : !primaryFilled
    property bool open: alwaysOpen || (primaryFilled && secondaryAvailable && (hovered || holdOpen))
    function boxColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1] ?? 1)
            : shell.role(spec, shell.foreground)
    }

    function hasVisibleContent(item) {
        if (!item) return false
        if (item.shown !== undefined) return item.shown
        if (item.text !== undefined) return String(item.text) !== ""
        if (item.empty !== undefined) return !item.empty
        return item.visible
    }

    readonly property real borderWidth: borderColor.a === 0 ? 0 : box.borderWidth
    readonly property real horizontalInsets: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * borderWidth
    readonly property real verticalInsets: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderWidth
    implicitWidth: empty ? 0 : content.implicitWidth + horizontalInsets
    implicitHeight: empty ? 0 : content.implicitHeight + verticalInsets
    clip: true

    Behavior on implicitWidth { enabled: !root.alwaysOpen; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { enabled: !root.alwaysOpen; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius; color: root.backgroundColor
        border.color: root.hovered ? root.hoverBorderColor : root.borderColor
        border.width: root.borderWidth
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    GridLayout {
        id: content
        anchors.left: !root.drawersBeforePrimary ? parent.left : undefined
        anchors.right: root.drawersBeforePrimary ? parent.right : undefined
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: root.box.margin[0] + root.borderWidth + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.borderWidth + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.borderWidth + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.borderWidth + root.box.padding[3]
        rows: 1
        columns: root.slotComponents.length
        rowSpacing: 0
        columnSpacing: 0
        Loader {
            id: primaryLoader
            sourceComponent: root.slotComponents[0] || null
            visible: !root.alwaysOpen || root.primaryFilled
            Layout.fillHeight: true
            Layout.column: root.drawersBeforePrimary ? root.slotComponents.length - 1 : 0
        }
        Repeater {
            model: root.drawerSlots
            delegate: Loader {
                id: drawerLoader
                required property var modelData
                required property int index
                readonly property bool filled: root.hasVisibleContent(drawerLoader.item)
                readonly property int place: root.drawersBeforePrimary ? root.slotComponents.length - 2 - drawerLoader.index : drawerLoader.index + 1
                sourceComponent: root.secondaryAvailable && (root.alwaysOpen || root.preload || root.hovered || root.holdOpen) ? drawerLoader.modelData : null
                Layout.fillHeight: true
                Layout.column: drawerLoader.place
                opacity: root.open && drawerLoader.filled ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }
    HoverHandler { id: hover }
}

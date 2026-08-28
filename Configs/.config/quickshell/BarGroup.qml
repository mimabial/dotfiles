import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    // a group holds N children: slots[0] is always visible, the rest reveal on
    // hover. primary/secondary are the two-slot spelling of the same thing.
    property Component primary
    property Component secondary
    property var slots: []
    readonly property var chain: slots.length ? slots : [primary, secondary].filter(c => c)
    readonly property var drawerSlots: chain.slice(1)
    property bool vertical: true
    // which end the drawer grows toward; an alwaysOpen group reveals nothing, so
    // it has no growth direction and keeps its slots in array order
    property bool reverse: false
    property bool holdOpen: false
    // a container rather than a drawer: every slot is loaded and shown, and the
    // group sizes to whatever is visible instead of collapsing with slots[0]
    property bool alwaysOpen: false
    property bool secondaryAvailable: true
    // build the drawer up front instead of on hover: a slot whose script has
    // not printed yet has no width, and the group would open twice
    property bool preload: false
    property real radius: shell.moduleRadius
    property color fill: "transparent"
    property color outline: root.boxColor("outline")
    property color hoverOutline: {
        const spec = box.hover && "outline" in box.hover ? box.hover.outline : ["hvr_br", Style.hoverBorderAlpha]
        return !spec ? "transparent" : Array.isArray(spec) ? shell.alpha(shell.role(spec[0], outline), spec[1]) : shell.role(spec, outline)
    }
    readonly property bool hovered: hover.hovered
    readonly property bool primaryVisible: head.item && head.item.visible
    readonly property bool ordered: reverse && !alwaysOpen
    readonly property bool empty: alwaysOpen ? content.implicitHeight <= 0 && content.implicitWidth <= 0 : !primaryVisible
    property bool open: alwaysOpen || (primaryVisible && secondaryAvailable && (hovered || holdOpen))
    // "outline": "br" or ["br", 0.3] in the style file; an explicit QML
    // assignment still overrides the binding
    function boxColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1])
            : shell.role(spec, shell.foreground)
    }

    readonly property real borderWidth: drawerEdge.replacesOutline ? 0 : outline.a > 0 ? Math.max(1, box.border) : 0
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * borderWidth
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderWidth
    implicitWidth: empty ? 0 : content.implicitWidth + spanX
    implicitHeight: empty ? 0 : content.implicitHeight + spanY
    clip: true

    Behavior on implicitWidth { enabled: !root.alwaysOpen; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { enabled: !root.alwaysOpen; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius; color: root.fill
        border.color: root.hovered ? root.hoverOutline : root.outline
        border.width: root.borderWidth
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    GridLayout {
        id: content
        anchors.left: root.vertical || !root.ordered ? parent.left : undefined
        anchors.right: root.vertical || root.ordered ? parent.right : undefined
        anchors.top: !root.vertical || !root.ordered ? parent.top : undefined
        anchors.bottom: !root.vertical || root.ordered ? parent.bottom : undefined
        anchors.topMargin: root.box.margin[0] + root.borderWidth + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.borderWidth + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.borderWidth + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.borderWidth + root.box.padding[3]
        rows: root.vertical ? root.chain.length : 1
        columns: root.vertical ? 1 : root.chain.length
        rowSpacing: 0
        columnSpacing: 0
        Loader {
            id: head
            sourceComponent: root.chain[0] || null
            Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
            Layout.row: root.vertical && root.ordered ? root.chain.length - 1 : 0
            Layout.column: !root.vertical && root.ordered ? root.chain.length - 1 : 0
        }
        Repeater {
            model: root.drawerSlots
            delegate: Loader {
                id: slot
                required property var modelData
                required property int index
                // a script that prints nothing hides its button, and an empty
                // drawer is worse than no drawer. `visible` is inherited from the
                // closed loader, so ask the button for its own text instead
                readonly property bool filled: !slot.item ? false
                    : slot.item.shown !== undefined ? slot.item.shown
                    : slot.item.text === undefined ? true
                    : String(slot.item.text) !== ""
                readonly property int place: root.ordered ? root.chain.length - 2 - slot.index : slot.index + 1
                sourceComponent: root.secondaryAvailable && (root.alwaysOpen || root.preload || root.hovered || root.holdOpen) ? slot.modelData : null
                Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
                Layout.row: root.vertical ? slot.place : 0
                Layout.column: root.vertical ? 0 : slot.place
                opacity: root.open && slot.filled ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }
    HoverHandler { id: hover }
    ModuleEdge { id: drawerEdge; shell: root.shell; hovered: hover.hovered }
}

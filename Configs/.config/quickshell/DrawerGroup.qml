import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    property Component primary
    property Component secondary
    property bool vertical: true
    property bool reverse: false
    property bool holdOpen: false
    property bool secondaryAvailable: true
    property real radius: shell.moduleRadius
    property color fill: "transparent"
    property color outline: root.boxColor("outline")
    readonly property bool primaryVisible: first.item && first.item.visible
    // a script that prints nothing hides its button, and an empty drawer is
    // worse than no drawer. `visible` is inherited from the closed loader, so
    // it always reads false here — ask the button for its own text instead
    readonly property bool secondaryVisible: !second.item ? false
        : second.item.text === undefined ? true
        : String(second.item.text) !== ""
    property bool open: primaryVisible && secondaryAvailable && secondaryVisible && (hover.hovered || holdOpen)
    // "outline": "br" or ["br", 0.3] in the style file; an explicit QML
    // assignment still overrides the binding
    function boxColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1])
            : shell.role(spec, shell.foreground)
    }

    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
    implicitWidth: !primaryVisible ? 0 : spanX + (vertical ? Math.max(first.implicitWidth, second.implicitWidth) : first.implicitWidth + (open ? second.implicitWidth : 0))
    implicitHeight: !primaryVisible ? 0 : spanY + (vertical ? first.implicitHeight + (open ? second.implicitHeight : 0) : Math.max(first.implicitHeight, second.implicitHeight))
    clip: true

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius; color: root.fill
        border.color: root.outline
        border.width: drawerEdge.replacesOutline ? 0 : root.outline.a > 0 ? Math.max(1, root.box.border) : 0
    }
    GridLayout {
        anchors.left: root.vertical || !root.reverse ? parent.left : undefined
        anchors.right: root.vertical || root.reverse ? parent.right : undefined
        anchors.top: !root.vertical || !root.reverse ? parent.top : undefined
        anchors.bottom: !root.vertical || root.reverse ? parent.bottom : undefined
        anchors.topMargin: root.box.margin[0] + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3]
        rows: root.vertical ? 2 : 1
        columns: root.vertical ? 1 : 2
        rowSpacing: 0
        columnSpacing: 0
        Loader {
            id: first
            sourceComponent: root.primary
            Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
            Layout.row: root.vertical && root.reverse ? 1 : 0
            Layout.column: !root.vertical && root.reverse ? 1 : 0
        }
        Loader {
            id: second
            sourceComponent: root.secondaryAvailable && (hover.hovered || root.holdOpen) ? root.secondary : null
            Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
            Layout.row: root.vertical && root.reverse ? 0 : root.vertical ? 1 : 0
            Layout.column: !root.vertical && root.reverse ? 0 : root.vertical ? 0 : 1
            opacity: root.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }
    HoverHandler { id: hover }
    ModuleEdge { id: drawerEdge; shell: root.shell; hovered: hover.hovered }
}

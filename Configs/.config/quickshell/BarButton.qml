import QtQuick

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    property string text: ""
    property string tooltip: ""
    property bool keyboardEnabled: false
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    // set by any PopupCard anchored here: a module with a panel never tooltips
    property bool hasPopup: false
    property bool active: false
    // Markup is not label text: a provider that wraps its glyph in <b> is still
    // an icon button.
    readonly property string labelText: text.replace(/<[^>]*>/g, "")
    // Match the icon ranges themselves rather than "holds no Latin": the old
    // test classified a Devanagari or kanji workspace numeral as an icon, so it
    // drew in the icon face and took its size correction. Plane-15 glyphs match
    // by their surrogate halves - Qt's JS engine honours a braced escape for a
    // single code point but not for a range inside a character class.
    readonly property bool iconOnly: labelText.length > 0
        && !/[^\ue000-\uf8ff\ud800-\udfff\u23fb-\u23fe\u2b58]/.test(labelText)
    property real fontSize: Style.fontPx(box.fontSize)
    // the icon face is scaled to match the text face's cap height, so anything
    // measuring this label has to measure the size it is actually drawn at
    readonly property real labelFontSize: iconOnly ? fontSize * shell.iconFontScale : fontSize
    property int fontWeight: box.fontWeight
    property int textFormat: Text.AutoText
    property real textOffsetX: 0
    property real fixedWidth: 0
    // waybar's per-module "justify"; multi-line modules line their values up on one edge
    readonly property int align: box.justify === "right" ? Text.AlignRight
        : box.justify === "left" ? Text.AlignLeft : Text.AlignHCenter
    property real radius: shell.moduleRadius
    readonly property bool hovered: mouse.containsMouse
    property color fill: root.boxColor("fill")
    property color outline: root.boxColor("outline")
    readonly property color baseFill: active && box.fill === undefined ? shell.alpha(shell.role("act_bg", shell.accent), .2) : fill
    readonly property color baseOutline: active && box.outline === undefined ? shell.role("act_br", shell.accent) : outline
    property color cornerOutline: "transparent"
    property color textColor: box.content !== undefined ? boxColor("content") : active ? shell.role("act_fg", shell.foreground) : shell.foreground
    property var hoverOverride: null
    property bool smoothTextColor: true
    signal clicked(int button)
    signal wheeled(int delta)

    // "outline": "br" or ["br", 0.3] in the style file; an explicit QML
    // assignment still overrides the binding
    function boxColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1])
            : shell.role(spec, shell.foreground)
    }

    // waybar's :hover recolours only the channels its CSS names, and never
    // touches border-width — a module with no border keeps none while hovered.
    // Buttons with no css key have no hover map to read, and would otherwise be
    // inert; they fall back to lifting the surface with the foreground, which is
    // the one role that reads against any of these backgrounds.
    function hoverPaint(key, fallback) {
        if (!hovered) return fallback
        if (hoverOverride && key in hoverOverride) return hoverOverride[key]
        if (box.hover && !(key in box.hover)) return fallback
        if (!box.hover) {
            if (key === "fill") return shell.alpha(shell.foreground, .1)
            // only recolour a border that is actually drawn
            if (key === "outline" && fallback.a > 0)
                return shell.alpha(shell.role("br", shell.foreground), .6)
            return fallback
        }
        const spec = box.hover[key]
        return spec ? shell.alpha(shell.role(spec[0], fallback), spec[1]) : "transparent"
    }

    // the frame the Rectangle actually paints; span and inset have to agree with it
    readonly property real borderWidth: edge.replacesOutline ? 0 : box.border > 0 ? box.border : active && box.outline === undefined ? 1.6 : baseOutline.a > 0 ? 1 : 0
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * borderWidth
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderWidth
    implicitWidth: fixedWidth > 0 ? fixedWidth : Math.max(box.minWidth, label.implicitWidth) + spanX
    implicitHeight: Math.max(box.minHeight, label.implicitHeight) + spanY

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius
        color: root.cursored ? root.shell.hoverFill() : root.hoverPaint("fill", root.baseFill)
        border.color: root.cursored ? root.shell.hoverEdge(.85) : root.hoverPaint("outline", root.baseOutline)
        border.width: root.cursored ? 2 : root.borderWidth
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    Text {
        id: label
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0] + root.borderWidth + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.borderWidth + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.borderWidth + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.borderWidth + root.box.padding[3]
        color: root.hoverPaint("content", root.textColor)
        Behavior on color { enabled: root.smoothTextColor; ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        font.family: root.iconOnly ? root.shell.iconGlyphFont : root.shell.fontFamily
        font.pixelSize: root.labelFontSize
        font.weight: root.fontWeight
        transform: Translate { x: root.textOffsetX }
        textFormat: root.textFormat
        horizontalAlignment: root.align
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.text
    }
    Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 8; anchors.rightMargin: 2; height: 1; visible: root.cornerOutline.a > 0; color: root.cornerOutline }
    Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 2; anchors.bottomMargin: 8; width: 1; visible: root.cornerOutline.a > 0; color: root.cornerOutline }
    ModuleEdge { id: edge; shell: root.shell; hovered: root.hovered; active: root.active }
    MouseArea {
        id: mouse
        // a derived type's children stack above the base's, and a rich-text Text
        // accepts hover events, so the hit area has to sit on top of them
        z: 1
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: event => { tip.dismiss(); root.clicked(event.button) }
        onWheel: event => root.wheeled(event.angleDelta.y)
    }
    BarTooltip { id: tip; anchorItem: root; shell: root.shell; text: root.tooltip; hovered: mouse.containsMouse && !root.hasPopup }
}

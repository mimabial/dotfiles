import QtQuick

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    property string text: ""
    property string leadingIcon: ""
    property real leadingIconGap: Style.px(4)
    property string tooltip: ""
    property bool keyboardEnabled: true
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    // PopupCards anchored here register themselves; opensPopup covers lazy
    // panels and panels anchored to a parent or sibling instead.
    property bool opensPopup: false
    property var popupCards: []
    readonly property bool hasPopup: root.opensPopup || root.popupCards.length > 0
    property bool active: false
    readonly property string labelText: text.replace(/<[^>]*>/g, "")
    // Match the icon ranges themselves rather than "holds no Latin": the old
    // test classified a Devanagari or kanji workspace numeral as an icon, so it
    // drew in the icon face and took its size correction. Plane-15 glyphs match
    // by their surrogate halves - Qt's JS engine honours a braced escape for a
    // single code point but not for a range inside a character class.
    readonly property bool usesIconFont: labelText.length > 0
        && !/[^\ue000-\uf8ff\ud800-\udfff\u23fb-\u23fe\u2b58]/.test(labelText)
    property real fontSize: Style.fontPx(box.fontSize)
    readonly property real renderedFontSize: usesIconFont ? fontSize * shell.iconFontScale : fontSize
    readonly property real leadingIconSize: fontSize * shell.iconFontScale
    property int fontWeight: box.fontWeight
    property int textFormat: Text.AutoText
    property real textOffsetX: 0
    property real textRotation: 0
    property real fixedWidth: 0
    property real maxWidth: 0
    readonly property int textAlignment: box.justify === "right" ? Text.AlignRight
        : box.justify === "left" ? Text.AlignLeft : Text.AlignHCenter
    property real radius: box.borderRadius ?? shell.moduleRadius
    readonly property bool hovered: mouse.containsMouse
    readonly property bool popupOpen: popupCards.some(card => card.open)
    property color backgroundColor: root.styleColor("backgroundColor")
    property color borderColor: root.styleColor("borderColor")
    property color cornerOutline: "transparent"
    property color textColor: box.color !== undefined ? styleColor("color") : active ? shell.role("act_fg", shell.foreground) : shell.foreground
    property var hoverOverride: null
    // drawn as an exponent past the glyph's top-right; countGlyph() fills it
    property string badgeText: ""
    property bool smoothTextColor: true
    signal clicked(int button)
    signal wheeled(int delta)
    onHoveredChanged: if (hovered && box.menuTracking && hasPopup && !popupOpen && shell.popupName !== "") clicked(Qt.LeftButton)

    function styleColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1] ?? 1)
            : shell.role(spec, shell.foreground)
    }

    // md-numeric_<n> runs contiguously from 0; md-numeric_9_plus draws at half height, so 9+ is md-numeric_9 + md-plus_thick
    function countGlyph(count) { return count > 9 ? "\u{f0b42}\u{f11ec}" : String.fromCodePoint(0xf0b39 + count) }

    function interactiveColor(key, fallback) {
        if (!hovered) return fallback
        if (hoverOverride && key in hoverOverride) return hoverOverride[key]
        if (box.hover && !(key in box.hover)) return fallback
        if (!box.hover) {
            if (key === "backgroundColor") return shell.alpha(shell.foreground, .1)
            if (key === "borderColor" && fallback.a > 0)
                return shell.alpha(shell.role("br", shell.foreground), .6)
            return fallback
        }
        const spec = box.hover[key]
        return !spec ? "transparent" : Array.isArray(spec)
            ? shell.alpha(shell.role(spec[0], fallback), spec[1] ?? 1) : shell.role(spec, fallback)
    }

    property real borderWidth: box.borderWidth
    readonly property real paintedBorderWidth: sideBorder.replacesBorder || borderColor.a === 0 ? 0 : borderWidth
    readonly property real horizontalInsets: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * paintedBorderWidth
    readonly property real verticalInsets: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * paintedBorderWidth
    readonly property real leadingIconWidth: leadingIcon !== "" ? icon.implicitWidth + (text !== "" ? leadingIconGap : 0) : 0
    readonly property real naturalWidth: Math.max(box.minWidth, label.implicitWidth + leadingIconWidth) + horizontalInsets
    implicitWidth: fixedWidth > 0 ? fixedWidth : maxWidth > 0 ? Math.min(naturalWidth, maxWidth) : naturalWidth
    implicitHeight: Math.max(box.minHeight, label.implicitHeight, leadingIcon !== "" ? icon.implicitHeight : 0) + verticalInsets
    readonly property rect paintedLabelBounds: Qt.rect(
        label.x + textOffsetX + (textAlignment === Text.AlignLeft ? 0
            : textAlignment === Text.AlignRight ? label.width - label.paintedWidth
            : (label.width - label.paintedWidth) / 2),
        label.y + (label.height - label.paintedHeight) / 2,
        label.paintedWidth, label.paintedHeight)

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius
        color: root.cursored ? root.shell.hoverFill()
            : root.popupOpen && root.box.open ? root.shell.styleColor(root.box.open.backgroundColor, root.backgroundColor)
            : root.interactiveColor("backgroundColor", root.backgroundColor)
        border.color: root.cursored ? root.shell.hoverEdge(.85) : root.interactiveColor("borderColor", root.borderColor)
        border.width: root.cursored ? 2 : root.paintedBorderWidth
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    Text {
        id: icon
        visible: root.leadingIcon !== ""
        anchors.left: parent.left
        anchors.leftMargin: root.box.margin[3] + root.paintedBorderWidth + root.box.padding[3]
        anchors.verticalCenter: parent.verticalCenter
        text: root.leadingIcon
        color: root.box.iconColor === undefined ? label.color : root.interactiveColor("iconColor", root.styleColor("iconColor"))
        Behavior on color { enabled: root.smoothTextColor; ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        font.family: root.shell.iconGlyphFont
        font.pixelSize: root.leadingIconSize
    }
    Text {
        id: label
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0] + root.paintedBorderWidth + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.paintedBorderWidth + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.paintedBorderWidth + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.paintedBorderWidth + root.box.padding[3] + root.leadingIconWidth
        color: root.interactiveColor("color", root.textColor)
        Behavior on color { enabled: root.smoothTextColor; ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        font.family: root.usesIconFont ? root.shell.iconGlyphFont : root.shell.fontFamily
        font.pixelSize: root.renderedFontSize
        font.weight: root.fontWeight
        transform: Translate { x: root.textOffsetX }
        rotation: root.textRotation
        textFormat: root.textFormat
        horizontalAlignment: root.textAlignment
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.text
    }
    Text {
        visible: root.badgeText !== ""
        x: root.paintedLabelBounds.x + root.paintedLabelBounds.width + (root.box.badgeOffsetX || 0)
        y: root.paintedLabelBounds.y + (root.box.badgeOffsetY || 0)
        text: root.badgeText
        color: root.box.badgeColor === undefined ? label.color : root.styleColor("badgeColor")
        font.family: root.shell.iconGlyphFont
        font.pixelSize: Style.px(root.box.badgeSize || 9)
    }
    Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 8; anchors.rightMargin: 2; height: 1; visible: root.cornerOutline.a > 0; color: root.cornerOutline }
    Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: 2; anchors.bottomMargin: 8; width: 1; visible: root.cornerOutline.a > 0; color: root.cornerOutline }
    SideBorder { id: sideBorder; shell: root.shell; host: root; hovered: root.hovered }
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

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
    id: root
    required property var shell
    property string css: ""
    readonly property var box: shell.style.box(css)
    property string text: ""
    property string leadingIcon: ""
    property real leadingIconGap: Style.px(box.leadingIconGap ?? 4)
    property real trailingWidth: 0
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
    property real iconSize: 0
    property string symbol: ""
    property string symbolContext: "status"
    readonly property string firstGlyph: labelText ? String.fromCodePoint(labelText.codePointAt(0)) : ""
    readonly property string styledSymbol: typeof box.symbol === "string" ? box.symbol : box.symbol?.[firstGlyph] ?? ""
    readonly property string resolvedSymbol: symbol || styledSymbol
    readonly property bool symbolic: resolvedSymbol !== ""
    readonly property SymbolicIcon symbolIcon: symbolLoader.item as SymbolicIcon
    readonly property SymbolicIcon leadingSymbolIcon: leadingSymbolLoader.item as SymbolicIcon
    readonly property bool inlineSymbolic: symbol === "" && styledSymbol !== "" && !usesIconFont
    readonly property string renderedText: inlineSymbolic ? text.replace(firstGlyph, "").replace(/^ /, "") : text
    readonly property string renderedLeadingIcon: inlineSymbolic ? firstGlyph : leadingIcon
    readonly property string leadingSymbol: inlineSymbolic ? styledSymbol : typeof box.leadingSymbol === "string" ? box.leadingSymbol : box.leadingSymbol?.[leadingIcon] ?? ""
    readonly property bool boxedIcon: symbolic && !inlineSymbolic || usesIconFont && box.iconBox !== undefined
    readonly property real iconBoxPx: iconSize || Style.fontPx(box.iconBox ?? box.fontSize)
    readonly property int symbolSize: Math.round(box.symbolSize ?? (iconSize || iconBoxPx * 1.15))
    readonly property rect glyphInk: (glyphProbe.item as GlyphInk)?.ink ?? Qt.rect(0, 0, 0, 0)
    readonly property bool fitsIconBox: boxedIcon && glyphInk.width > 0 && iconBoxPx > 0
    readonly property real iconMaxAspect: 1.2
    readonly property real renderedFontSize: fitsIconBox ? Math.round(iconBoxPx / Math.max(glyphInk.height, glyphInk.width / iconMaxAspect))
        : usesIconFont ? fontSize * shell.iconFontScale : fontSize
    readonly property real leadingIconSize: Style.fontPx(box.leadingIconSize ?? box.fontSize) * shell.iconFontScale
    property int fontWeight: box.fontWeight
    property int textFormat: Text.AutoText
    readonly property real inkOffsetX: fitsIconBox ? label.contentWidth / 2 - label.font.pixelSize * (glyphInk.x + glyphInk.width / 2) : 0
    property real textOffsetX: inkOffsetX
    readonly property real textOffsetY: fitsIconBox ? label.height / 2 - label.baselineOffset - label.font.pixelSize * (glyphInk.y + glyphInk.height / 2) : 0
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
    readonly property color contentColor: label.color
    property var hoverOverride: null
    // drawn as an exponent past the glyph's top-right; countGlyph() fills it
    readonly property var badgeStyle: box.badges?.[firstGlyph] ?? ({})
    property string badgeText: badgeStyle.text ?? ""
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
    function countGlyph(count) {
        if (box.badgeNumerals === "standard") return count > 9 ? "9+" : String(count)
        return count > 9 ? "\u{f0b42}\u{f11ec}" : String.fromCodePoint(0xf0b39 + count)
    }

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
    readonly property real leadingIconWidth: renderedLeadingIcon !== "" ? icon.implicitWidth + (renderedText !== "" ? leadingIconGap : 0) : 0
    readonly property real naturalWidth: Math.max(box.minWidth, (symbolIcon?.loaded ? symbolIcon.ink.width
        : boxedIcon ? Math.max(iconBoxPx * iconMaxAspect, label.implicitWidth) : label.implicitWidth)
        + leadingIconWidth) + trailingWidth + horizontalInsets
    implicitWidth: fixedWidth > 0 ? fixedWidth : maxWidth > 0 ? Math.min(naturalWidth, maxWidth) : naturalWidth
    implicitHeight: Math.max(box.minHeight, boxedIcon ? iconBoxPx : label.implicitHeight, leadingIconMetrics.tightBoundingRect.height) + verticalInsets
    readonly property rect paintedLabelBounds: {
        if (symbolIcon?.loaded)
            return Qt.rect(symbolLoader.x + symbolIcon.ink.x, symbolLoader.y, symbolIcon.ink.width, symbolLoader.height)
        const size = label.font.pixelSize, tight = labelMetrics.tightBoundingRect
        const ink = fitsIconBox
            ? Qt.rect(size * glyphInk.x, label.baselineOffset + size * glyphInk.y, size * glyphInk.width, size * glyphInk.height)
            : usesIconFont ? Qt.rect(tight.x, label.baselineOffset + tight.y, tight.width, tight.height)
            : Qt.rect(0, (label.height - label.paintedHeight) / 2, label.paintedWidth, label.paintedHeight)
        const textWidth = fitsIconBox || usesIconFont ? label.contentWidth : label.paintedWidth
        const alignmentOffset = textAlignment === Text.AlignLeft ? 0
            : textAlignment === Text.AlignRight ? label.width - textWidth : (label.width - textWidth) / 2
        return Qt.rect(label.x + textOffsetX + alignmentOffset + ink.x,
            label.y + textOffsetY + ink.y, ink.width, ink.height)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        radius: root.radius
        color: root.cursored ? root.shell.hoverFill()
            : root.interactiveColor("backgroundColor", root.popupOpen && root.box.open
                ? root.shell.styleColor(root.box.open.backgroundColor, root.backgroundColor) : root.backgroundColor)
        border.color: root.cursored ? root.shell.hoverEdge(.85) : root.interactiveColor("borderColor", root.borderColor)
        border.width: root.cursored ? 2 : root.paintedBorderWidth
        Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
    }
    Loader { id: glyphProbe; active: root.boxedIcon && !root.symbolic; sourceComponent: Component { GlyphInk { glyph: root.labelText; family: root.shell.iconGlyphFont } } }
    Item {
        id: glyphs
        anchors.fill: parent
        layer.enabled: badge.visible && root.box.badgeBackgroundColor === null
        layer.effect: MultiEffect {
            maskEnabled: true; maskInverted: true; maskSource: badgeMask
            maskThresholdMin: 0.5; maskSpreadAtMin: 1
        }
        Loader {
            id: symbolLoader
            active: root.symbolic && !root.inlineSymbolic; anchors.verticalCenter: label.verticalCenter
            x: label.x + (label.width - (root.symbolIcon?.ink.width ?? width)) / 2 - (root.symbolIcon?.ink.x ?? 0)
            sourceComponent: Component { SymbolicIcon { name: root.resolvedSymbol; context: root.symbolContext; directory: root.box.symbols ?? ""; color: label.color; size: root.symbolSize } }
        }
        Item {
            id: icon
            visible: root.renderedLeadingIcon !== ""
            implicitWidth: root.leadingSymbolIcon?.loaded ? root.leadingSymbolIcon.ink.width : root.box.symbolSize ?? leadingGlyph.implicitWidth
            implicitHeight: root.box.symbolSize ?? leadingGlyph.implicitHeight
            anchors.left: parent.left
            anchors.leftMargin: root.box.margin[3] + root.paintedBorderWidth + root.box.padding[3]
            anchors.verticalCenter: parent.verticalCenter
            Loader {
                id: leadingSymbolLoader
                active: icon.visible && root.leadingSymbol !== ""; anchors.verticalCenter: parent.verticalCenter
                x: (icon.width - (root.leadingSymbolIcon?.ink.width ?? width)) / 2 - (root.leadingSymbolIcon?.ink.x ?? 0)
                sourceComponent: Component { SymbolicIcon { name: root.leadingSymbol; directory: root.box.symbols ?? ""; color: leadingGlyph.color; size: Math.round(root.box.symbolSize ?? leadingIconMetrics.tightBoundingRect.height) } }
            }
            Text {
                id: leadingGlyph
                visible: !(root.leadingSymbolIcon?.loaded ?? false)
                text: root.renderedLeadingIcon
                color: root.box.iconColor === undefined ? label.color : root.interactiveColor("iconColor", root.styleColor("iconColor"))
                Behavior on color { enabled: root.smoothTextColor; ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                font.family: root.shell.iconGlyphFont
                font.pixelSize: root.leadingIconSize
            }
        }
        TextMetrics { id: leadingIconMetrics; font: leadingGlyph.font; text: leadingGlyph.text }
        TextMetrics { id: labelMetrics; font: label.font; text: root.labelText }
        Text {
            id: label
            visible: !(root.symbolIcon?.loaded ?? false)
            anchors.fill: parent
            anchors.topMargin: root.box.margin[0] + root.paintedBorderWidth + root.box.padding[0]
            anchors.rightMargin: root.box.margin[1] + root.paintedBorderWidth + root.box.padding[1] + root.trailingWidth
            anchors.bottomMargin: root.box.margin[2] + root.paintedBorderWidth + root.box.padding[2]
            anchors.leftMargin: root.box.margin[3] + root.paintedBorderWidth + root.box.padding[3] + root.leadingIconWidth
            color: root.interactiveColor("color", root.textColor)
            Behavior on color { enabled: root.smoothTextColor; ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
            font.family: root.usesIconFont ? root.shell.iconGlyphFont : root.shell.fontFamily
            font.pixelSize: root.renderedFontSize
            font.weight: root.fontWeight
            transform: Translate { x: root.textOffsetX; y: root.textOffsetY }
            rotation: root.textRotation
            textFormat: root.textFormat
            horizontalAlignment: root.textAlignment
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.renderedText
        }
    }
    Item {
        id: badgeMask
        anchors.fill: glyphs
        visible: false; layer.enabled: glyphs.layer.enabled
        Rectangle {
            x: badgeBackground.x; y: badgeBackground.y
            width: badgeBackground.width; height: badgeBackground.height
            radius: badgeBackground.radius; color: "black"
        }
    }
    Rectangle { id: badgeBackground; anchors.fill: badge; anchors.leftMargin: -Style.xxs; anchors.rightMargin: -Style.xxs; radius: root.box.badgeBorderRadius === null ? root.shell.rounding : root.box.badgeBorderRadius ?? height / 2; visible: badge.visible; color: root.styleColor("badgeBackgroundColor") }
    TextMetrics { id: badgeMetrics; font: badge.font; text: badge.text }
    Text {
        id: badge
        readonly property real glyphCenterY: badge.baselineOffset + badgeMetrics.tightBoundingRect.y + badgeMetrics.tightBoundingRect.height / 2
        visible: root.badgeText !== ""
        x: root.paintedLabelBounds.x + root.paintedLabelBounds.width + (root.box.badgeOffsetX || 0)
        y: root.paintedLabelBounds.y - badge.glyphCenterY + (root.box.badgeOffsetY || 0)
        text: root.badgeText
        color: root.badgeStyle.color !== undefined ? root.shell.styleColor(root.badgeStyle.color, label.color)
            : root.box.badgeColor === undefined ? label.color : root.styleColor("badgeColor")
        font.family: root.box.badgeNumerals === "standard" ? root.shell.fontFamily : root.shell.iconGlyphFont
        font.pixelSize: Style.px(root.box.badgeSize || 9)
        font.weight: root.box.badgeFontWeight ?? Font.Normal
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
        cursorShape: Qt.PointingHandCursor
        onClicked: event => { tip.dismiss(); root.clicked(event.button) }
        onWheel: event => root.wheeled(event.angleDelta.y)
    }
    BarTooltip { id: tip; anchorItem: root; shell: root.shell; text: root.tooltip; hovered: mouse.containsMouse && !root.hasPopup }
}

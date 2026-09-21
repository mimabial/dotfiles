pragma Singleton
import QtQuick
import ".." as Active

QtObject {
    id: root

    property var shell: null

    readonly property int textSize: Active.Style.textSize
    readonly property int cornerRadius: root.shell ? Number(root.shell.rounding) : 0
    readonly property int gapsOut: Active.Style.popupGap
    readonly property string fontFamily:
        root.shell ? String(root.shell.fontFamily) : "JetBrainsMono Nerd Font"
    // What the bar and its popups actually paint, so a ported panel does not
    // end up the only opaque surface on the desktop.
    readonly property real barOpacity: root.shell ? Number(root.shell.barOpacity) : 1
    readonly property real popupSurfaceOpacity: Active.Style.popupSurfaceOpacity
    readonly property real popupBorderOpacity: Active.Style.popupBorderOpacity
    readonly property int hoverDuration: Active.Style.hoverDuration

    readonly property int normalBorderWidth: Math.max(1, Active.Style.px(1))
    readonly property int hoverBorderWidth: normalBorderWidth
    readonly property int selectedBorderWidth: 0
    readonly property int focusBorderWidth: hoverBorderWidth
    readonly property real normalFillAlpha: 0.04
    readonly property real selectedFillAlpha: 0.18
    readonly property real pressedFillAlpha: 0.22
    readonly property real focusFillAlpha: Active.Style.hoverFillAlpha
    readonly property real selectionFillAlpha: 0.35

    function normalFillFor(foreground, accent) {
        return Util.alpha(foreground || Color.foreground, normalFillAlpha)
    }

    function hoverFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground,
                          Active.Style.hoverFillAlpha)
    }
    function selectedFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground, selectedFillAlpha)
    }
    function pressedFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground, pressedFillAlpha)
    }
    function focusFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground, focusFillAlpha)
    }
    function selectionFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground, selectionFillAlpha)
    }
    function hoverStateColor(foreground, accent) { return accent || foreground || Color.foreground }
    function selectedStateColor(foreground, accent) { return accent || foreground || Color.foreground }
    function controlFill(focused, hot, foreground, accent) {
        return focused ? focusFillFor(foreground, accent)
             : hot ? hoverFillFor(foreground, accent)
             : normalFillFor(foreground, accent)
    }

    function space(value) {
        return Active.Style.px(Number(value))
    }

    function spaceReal(value) {
        return Number(value) * Active.Style.uiScale
    }

    readonly property StyleSpacing spacing: StyleSpacing {
        hairline: Math.max(1, Active.Style.px(1))
        xxs: Active.Style.xxs
        xs: Active.Style.xs
        sm: Active.Style.sm
        md: Active.Style.md
        lg: Active.Style.lg
        xl: Active.Style.xl
        huge: Active.Style.lg + Active.Style.md
        controlGap: Active.Style.md
        controlPaddingX: Active.Style.controlPaddingX
        controlPaddingY: Active.Style.controlPaddingY
        inputPaddingY: Active.Style.controlPaddingY
        controlHeight: Active.Style.controlHeight
        popupRowHeight: Active.Style.popupRowHeight
        dropdownWidth: Active.Style.px(240)
        numberFieldWidth: Active.Style.px(120)
        rowPaddingX: Active.Style.controlPaddingX
        labelGap: Active.Style.xs
        panelPadding: Active.Style.popupPadding
        popupPadding: Active.Style.popupPadding
    }

    // This config sizes its bars from their content, so there is no fixed bar
    // thickness token. controlHeight is the one-row metric and scales with
    // TEXT_SIZE, which is what consumers of sizeHorizontal actually want.
    readonly property StyleBar bar: StyleBar {
        sizeHorizontal: Active.Style.controlHeight
        iconSlot: Active.Style.controlHeight
        iconFont: Active.Style.title + 3
    }

    // Icon glyphs from the text font disagree on ink height — in Lekton the play
    // triangle is 0.810 em against the plus's 0.750 and the pause's 0.692 — so the
    // same pixelSize renders them at visibly different sizes. Measure the live face
    // and scale the odd ones onto the plus, the 0.750-em anchor.
    readonly property TextMetrics inkPlus: TextMetrics { font.family: root.fontFamily; font.pixelSize: 200; text: "\uf067" }
    readonly property TextMetrics inkPlay: TextMetrics { font.family: root.fontFamily; font.pixelSize: 200; text: "\uf04b" }
    readonly property TextMetrics inkPause: TextMetrics { font.family: root.fontFamily; font.pixelSize: 200; text: "\uf04c" }
    function iconScale(glyph) {
        const reference = root.inkPlus.tightBoundingRect.height
        if (!(reference > 0)) return 1
        const probe = glyph === "\uf04b" ? root.inkPlay : glyph === "\uf04c" ? root.inkPause : null
        const ink = probe ? probe.tightBoundingRect.height : 0
        return ink > 0 ? reference / ink : 1
    }

    readonly property StyleFont font: StyleFont {
        family: root.fontFamily
        menuFamily: root.fontFamily
        caption: Active.Style.caption
        bodySmall: Active.Style.bodySmall
        body: Active.Style.body
        title: Active.Style.title
        subtitle: Active.Style.subtitle
        heading: Active.Style.subtitle
        icon: Active.Style.title + 3
        display: Active.Style.display
        displayLarge: Active.Style.displayLarge
        iconLarge: Active.Style.title
    }
}

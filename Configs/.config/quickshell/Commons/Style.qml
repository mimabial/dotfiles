pragma Singleton
import QtQuick
import "." as Commons
import ".." as Active

QtObject {
    id: root

    property var shell: null

    readonly property int textSize: Active.Style.textSize
    readonly property real glyphOvershoot: Active.Style.glyphOvershoot
    readonly property int cornerRadius: root.shell ? Number(root.shell.rounding) : 0
    readonly property int gapsOut: Active.Style.popupGap
    readonly property string fontFamily:
        root.shell ? String(root.shell.fontFamily) : "JetBrainsMono Nerd Font"
    readonly property real barOpacity: root.shell ? Number(root.shell.barOpacity) : 1
    readonly property real popupSurfaceOpacity: Active.Style.popupSurfaceOpacity
    readonly property real popupBorderOpacity: Active.Style.popupBorderOpacity
    function popupTinted(base) { return Active.Style.popupTinted(base) }
    function popupBorder(base, opacity) { return Active.Style.popupBorder(base, opacity) }
    readonly property int hoverDuration: Active.Style.hoverDuration
    readonly property int confirmationShownMs: Active.Style.confirmationShownMs
    readonly property real secondaryTextAlpha: Active.Style.secondaryTextAlpha
    readonly property real mutedTextAlpha: Active.Style.mutedTextAlpha
    readonly property real faintTextAlpha: Active.Style.faintTextAlpha

    readonly property int normalBorderWidth: Math.max(1, Active.Style.px(1))
    readonly property real normalBorderAlpha: 0.38
    readonly property real normalFillAlpha: 0.04
    readonly property real selectedFillAlpha: Active.Style.selectedFillAlpha
    readonly property real pressedFillAlpha: 0.22
    readonly property real focusFillAlpha: Active.Style.hoverFillAlpha
    readonly property real selectionFillAlpha: 0.35

    function normalFillFor(foreground, accent) {
        return Util.scaleAlpha(foreground || Commons.Color.foreground, normalFillAlpha)
    }

    function hoverFillFor(foreground, accent) {
        return Util.scaleAlpha(accent || foreground || Commons.Color.foreground,
                          Active.Style.hoverFillAlpha)
    }
    function selectedFillFor(foreground, accent) {
        return Util.scaleAlpha(accent || foreground || Commons.Color.foreground, selectedFillAlpha)
    }
    function pressedFillFor(foreground, accent) {
        return Util.scaleAlpha(accent || foreground || Commons.Color.foreground, pressedFillAlpha)
    }
    function focusFillFor(foreground, accent) {
        return Util.scaleAlpha(accent || foreground || Commons.Color.foreground, focusFillAlpha)
    }
    function selectionFillFor(foreground, accent) {
        return Util.scaleAlpha(accent || foreground || Commons.Color.foreground, selectionFillAlpha)
    }
    function hoverStateColor(foreground, accent) { return accent || foreground || Commons.Color.foreground }
    function selectedStateColor(foreground, accent) { return accent || foreground || Commons.Color.foreground }
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

    function fontPx(nominalSize) {
        return Active.Style.fontPx(nominalSize)
    }

    readonly property Commons.StyleSpacing spacing: Commons.StyleSpacing {
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

    readonly property Commons.StyleBar bar: Commons.StyleBar {
        sizeHorizontal: Active.Style.controlHeight
        iconSlot: Active.Style.controlHeight
    }

    readonly property string plusGlyph: "\uf067"
    readonly property string playGlyph: "\uf04b"
    readonly property string pauseGlyph: "\uf04c"
    readonly property int inkProbePixelSize: 200
    readonly property TextMetrics inkPlus: TextMetrics { font.family: root.fontFamily; font.pixelSize: root.inkProbePixelSize; text: root.plusGlyph }
    readonly property TextMetrics inkPlay: TextMetrics { font.family: root.fontFamily; font.pixelSize: root.inkProbePixelSize; text: root.playGlyph }
    readonly property TextMetrics inkPause: TextMetrics { font.family: root.fontFamily; font.pixelSize: root.inkProbePixelSize; text: root.pauseGlyph }
    function iconScale(glyph) {
        const reference = root.inkPlus.tightBoundingRect.height
        if (!(reference > 0)) return 1
        const probe = glyph === root.playGlyph ? root.inkPlay : glyph === root.pauseGlyph ? root.inkPause : null
        const ink = probe ? probe.tightBoundingRect.height : 0
        return ink > 0 ? reference / ink : 1
    }

    readonly property Commons.StyleFont font: Commons.StyleFont {
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

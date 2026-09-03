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
    readonly property int normalBorderWidth: Math.max(1, Active.Style.px(1))
    readonly property int hoverBorderWidth: normalBorderWidth
    readonly property int selectedBorderWidth: 0
    readonly property int focusBorderWidth: hoverBorderWidth

    function hoverFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground,
                          Active.Style.hoverFillAlpha)
    }

    function space(value) {
        return Active.Style.px(Number(value))
    }

    readonly property StyleSpacing spacing: StyleSpacing {
        xs: Active.Style.xs
        sm: Active.Style.sm
        md: Active.Style.md
        lg: Active.Style.lg
        xl: Active.Style.xl
        panelPadding: Active.Style.popupPadding
    }

    readonly property StyleFont font: StyleFont {
        family: root.fontFamily
        menuFamily: root.fontFamily
        caption: Active.Style.caption
        bodySmall: Active.Style.bodySmall
        body: Active.Style.body
        title: Active.Style.title
        heading: Active.Style.subtitle
        display: Active.Style.display
        displayLarge: Active.Style.displayLarge
        iconLarge: Active.Style.title
    }
}

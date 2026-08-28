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
    readonly property real scale: Active.Style.scale
    readonly property int normalBorderWidth: Math.max(1, Active.Style.px(1))

    function hoverFillFor(foreground, accent) {
        return Util.alpha(accent || foreground || Color.foreground,
                          Active.Style.hoverFillAlpha)
    }

    function space(value) {
        return Active.Style.px(Number(value))
    }

    readonly property QtObject spacing: QtObject {
        readonly property int xs: Active.Style.xs
        readonly property int sm: Active.Style.sm
        readonly property int md: Active.Style.md
        readonly property int panelPadding: Active.Style.popupPadding
    }

    readonly property QtObject font: QtObject {
        readonly property string family: root.fontFamily
        readonly property string menuFamily: root.fontFamily
        readonly property int caption: Active.Style.caption
        readonly property int bodySmall: Active.Style.bodySmall
        readonly property int body: Active.Style.body
        readonly property int title: Active.Style.title
        readonly property int heading: Active.Style.subtitle
        readonly property int displayLarge: Active.Style.px(28)
        readonly property int iconLarge: Active.Style.title
    }
}

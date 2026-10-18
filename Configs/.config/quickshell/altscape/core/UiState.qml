import QtQuick
import qs as Bar

Item {
    id: root

    visible: false

    required property var shell

    property color barFg: "white"
    property color barBg: "#121217"
    property color themeAccent: "transparent"
    property string fontName: ""

    function lumOf(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    
    function contrast(c) {
        return lumOf(c) > 0.5 ? Qt.rgba(0.08, 0.08, 0.08, 1) : Qt.rgba(0.96, 0.96, 0.96, 1)
    }

    readonly property color surface: Qt.rgba(barBg.r, barBg.g, barBg.b, 1)
    readonly property bool lightSurface: lumOf(surface) > 0.5
    readonly property color fg: barFg
    readonly property bool hasThemeAccent: themeAccent.a > 0
    readonly property color accent: hasThemeAccent ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 1) : barFg

    readonly property color accentText: contrast(accent)
    readonly property color bad: lightSurface ? Qt.rgba(0.74, 0.16, 0.26, 1) : Qt.rgba(0.97, 0.46, 0.56, 1)

    readonly property bool animations: !Bar.Style.reduceMotion

    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    
    
    readonly property real panelCornerScale: 3
    function cornerRadius(scale) { return root.shell.rounding * scale / panelCornerScale }
    function fontPx(n) { return Bar.Style.fontPx(n) }
    function px(n) { return Bar.Style.px(n) }
}

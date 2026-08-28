pragma Singleton
import QtQuick

QtObject {
    id: root

    property var shell: null

    function alpha(color, opacity) {
        if (root.shell)
            return root.shell.alpha(color, opacity)
        return Qt.rgba(color.r, color.g, color.b,
                       (color.a === undefined ? 1 : color.a) * opacity)
    }

    function role(name, fallback) {
        return root.shell ? root.shell.role(name, fallback) : fallback
    }

    readonly property color foreground:
        root.shell ? root.shell.foreground : "#ffffff"
    readonly property color background: role("bg", "#11111b")
    readonly property color accent:
        root.shell ? root.shell.accent : foreground
    readonly property color urgent: role("error", "#f38ba8")

    readonly property QtObject popups: QtObject {
        readonly property color background: root.background
        readonly property color text: root.foreground
        readonly property color border: root.alpha(root.role("alt_br", root.accent), 0.45)
    }

    readonly property QtObject menu: QtObject {
        readonly property color background: root.background
        readonly property color text: root.foreground
        readonly property color border: root.alpha(root.role("alt_br", root.accent), 0.45)
        readonly property color scrim: root.alpha(root.background, 0.72)
        readonly property color selectedBackground:
            root.shell ? root.shell.hoverFill(2)
                       : root.alpha(root.role("hvr_bg", root.accent), 0.25)
        readonly property color selectedText: root.role("hvr_fg", root.accent)
        readonly property color selectedBorder:
            root.shell ? root.shell.hoverEdge(1)
                       : root.alpha(root.role("hvr_br", root.accent), 0.55)
    }
}

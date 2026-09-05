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

    readonly property ColorBar bar: ColorBar {
        background: root.background
        text: root.foreground
        active: root.accent
    }

    readonly property ColorTooltip tooltip: ColorTooltip {
        background: root.background
        text: root.foreground
        border: root.alpha(root.role("alt_br", root.accent), 0.45)
    }

    readonly property ColorPopups popups: ColorPopups {
        background: root.background
        text: root.foreground
        border: root.alpha(root.role("alt_br", root.accent), 0.45)
    }

    readonly property ColorMenu menu: ColorMenu {
        background: root.background
        text: root.foreground
        border: root.alpha(root.role("alt_br", root.accent), 0.45)
        scrim: root.alpha(root.background, 0.72)
        selectedBackground:
            root.shell ? root.shell.hoverFill(2)
                       : root.alpha(root.role("hvr_bg", root.accent), 0.25)
        selectedText: root.role("hvr_fg", root.accent)
        selectedBorder:
            root.shell ? root.shell.hoverEdge(1)
                       : root.alpha(root.role("hvr_br", root.accent), 0.55)
    }
}

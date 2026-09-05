pragma Singleton
import QtQuick

QtObject {
    function widths(value) {
        const width = Math.max(0, Number(value) || 0)
        return { top: width, right: width, bottom: width, left: width }
    }

    function none() { return flat("transparent", 0) }
    function flat(color, width) { return { color: color || "transparent", widths: widths(width) } }
    function surfaceSpec(section, token, fallbackColor, fallbackWidth) {
        return flat(fallbackColor, fallbackWidth)
    }
    function localOrSurfaceSpec(section, token, localColor, fallbackColor, fallbackWidth) {
        return flat(localColor || fallbackColor, fallbackWidth)
    }
    function controlHasWidth(state) {
        return state !== "selected" || Style.selectedBorderWidth > 0
    }
    function controlSpec(state, foreground, accent, urgent) {
        const focused = ["focus", "focused", "selected"].includes(state)
        const color = focused ? (accent || foreground)
                              : Color.alpha(foreground || Color.foreground, 0.4)
        return flat(color, 1)
    }

    function top(spec) { return spec && spec.widths ? spec.widths.top : 0 }
    function right(spec) { return spec && spec.widths ? spec.widths.right : 0 }
    function bottom(spec) { return spec && spec.widths ? spec.widths.bottom : 0 }
    function left(spec) { return spec && spec.widths ? spec.widths.left : 0 }
    function color(spec) { return spec ? spec.color : "transparent" }
    function uniformWidth(spec) { return top(spec) }
}

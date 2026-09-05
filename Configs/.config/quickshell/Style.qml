pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared spacing and type tokens. Every popup metric comes from here — a value
// invented at a use site is how the padding drifted in the first place.
Singleton {
    id: root
    readonly property int xxs: px(2)
    readonly property int xs: px(3)
    readonly property int sm: px(4)
    readonly property int md: px(6)
    readonly property int lg: px(8)
    readonly property int xl: px(10)
    readonly property int xxl: px(12)
    readonly property int xxxl: px(14)

    readonly property int popupGap: 5
    readonly property int popupPadding: px(14)
    readonly property int sectionGap: px(14)    // between popup sections
    readonly property int rowGap: px(8)
    readonly property int controlGap: px(8)
    readonly property int controlPaddingX: px(10)
    readonly property int controlPaddingY: px(6)
    readonly property int controlHeight: px(28)
    readonly property int popupRowHeight: px(28)

    readonly property int trackHeight: Math.max(4, Math.round(controlHeight * 0.11))
    readonly property int knobSize: Math.max(14, Math.round(controlHeight * 0.38))
    readonly property int sliderHeight: knobSize + sm

    // Popup surfaces. PopupCard defaults from these, and the qs.Commons shim
    // re-exports them so ported panels land on the same glass as the bar's own.
    readonly property real popupSurfaceOpacity: 0.92
    readonly property real popupBorderOpacity: 0.45

    readonly property real hoverFillAlpha: 0.12
    readonly property real hoverBorderAlpha: 0.55
    readonly property int hoverDuration: 180
    readonly property int tooltipDelay: 400

    // hyprshell system/text-size writes the application body size directly.
    property int textSize: 12
    readonly property real uiScale: textSize / 12
    function px(size) { return Math.round(size * uiScale) }
    function fontPx(nominalSize) { return Math.round(nominalSize * textSize / 12) }
    function typePx(ratio) { return Math.max(1, Math.round(textSize * ratio)) }

    readonly property int caption: typePx(0.78)
    readonly property int bodySmall: typePx(0.89)
    readonly property int body: textSize
    readonly property int subtitle: body
    readonly property int title: body
    readonly property int display: body
    readonly property int displayLarge: body
    readonly property int heroIcon: typePx(1.78)

    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/hypr/staterc"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const match = String(text()).match(/(?:^|\n)TEXT_SIZE=["']?(\d+)/)
            root.textSize = match ? parseInt(match[1]) : 12
        }
    }
}

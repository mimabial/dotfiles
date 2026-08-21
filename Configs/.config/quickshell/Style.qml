pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared spacing and type tokens, mirroring omarchy's qs.Commons Style so the
// two codebases stay comparable. Every popup metric comes from here — a value
// invented at a use site is how the padding drifted in the first place.
Singleton {
    id: root
    readonly property int xxs: 2
    readonly property int xs: 3
    readonly property int sm: 4
    readonly property int md: 6
    readonly property int lg: 8
    readonly property int xl: 10
    readonly property int xxl: 12
    readonly property int xxxl: 14

    readonly property int popupGap: 5           // omarchy gapsOut — card offset from the bar
    readonly property int popupPadding: 14
    readonly property int sectionGap: 14        // between popup sections
    readonly property int rowGap: 8
    readonly property int controlGap: 8
    readonly property int controlPaddingX: 10
    readonly property int controlPaddingY: 6
    readonly property int controlHeight: 28
    readonly property int popupRowHeight: 28

    readonly property int trackHeight: Math.max(4, Math.round(controlHeight * 0.11))
    readonly property int knobSize: Math.max(14, Math.round(controlHeight * 0.38))
    readonly property int sliderHeight: knobSize + sm

    readonly property real hoverFillAlpha: 0.12
    readonly property real hoverBorderAlpha: 0.55
    readonly property int hoverDuration: 180
    readonly property int tooltipDelay: 400

    // hyprshell system/text-size writes TEXT_SIZE; 12px is the 1.0 anchor.
    property int textSize: 12
    readonly property real scale: textSize / 12
    function px(size) { return Math.round(size * scale) }

    readonly property int caption: px(10)
    readonly property int bodySmall: px(11)
    readonly property int body: px(12)
    readonly property int subtitle: px(13)
    readonly property int title: px(14)

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

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    readonly property var popupStyle: JSON.parse(popupStyleFile.text())
    property FileView popupStyleFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/styles/popup.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property int xxs: px(2)
    readonly property int xs: px(3)
    readonly property int sm: px(4)
    readonly property int md: px(6)
    readonly property int lg: px(8)
    readonly property int xl: px(10)
    readonly property int xxl: px(12)
    readonly property int xxxl: px(14)

    readonly property int popupGap: 5
    readonly property int popupPadding: px(popupStyle.popupPadding)
    readonly property int sectionGap: px(popupStyle.sectionGap)
    readonly property int rowGap: px(popupStyle.rowGap)
    readonly property int controlGap: px(popupStyle.controlGap)
    readonly property int controlPaddingX: px(popupStyle.controlPaddingX)
    readonly property int controlPaddingY: px(popupStyle.controlPaddingY)
    readonly property int controlHeight: px(popupStyle.controlHeight)
    readonly property int popupRowHeight: px(popupStyle.popupRowHeight)

    readonly property int trackHeight: Math.max(4, Math.round(controlHeight * 0.11))
    readonly property int knobSize: Math.max(14, Math.round(controlHeight * 0.38))
    readonly property int sliderHeight: knobSize + sm

    readonly property int spotlightWidth: px(750)
    readonly property int spotlightSearchHeight: px(56)
    readonly property int spotlightSectionHeight: px(24)
    readonly property int spotlightListHeight: px(456)

    readonly property real defaultPopupSurfaceOpacity: popupStyle.defaultSurfaceOpacity
    property real popupSurfaceOpacity: defaultPopupSurfaceOpacity
    readonly property real popupBorderOpacity: popupStyle.borderOpacity
    readonly property real maxPopupTint: 0.3
    property color popupTint: "transparent"
    function popupTinted(base) { return Qt.tint(base, popupTint) }
    property bool popupBorders: true
    property color popupBorderOverride: "transparent"
    function popupBorder(base, opacity) {
        const color = popupBorderOverride.a > 0 ? popupBorderOverride : base
        return Qt.rgba(color.r, color.g, color.b, popupBorders ? (opacity ?? color.a) : 0)
    }

    readonly property real hoverFillAlpha: popupStyle.hoverFillAlpha
    readonly property real hoverBorderAlpha: 0.55
    readonly property real selectedFillAlpha: popupStyle.selectedFillAlpha
    readonly property real selectedBorderAlpha: 0.5
    readonly property real fieldFillAlpha: popupStyle.fieldFillAlpha
    readonly property real fieldBorderAlpha: popupStyle.fieldBorderAlpha
    readonly property real secondaryTextAlpha: 0.7
    readonly property real mutedTextAlpha: popupStyle.mutedTextAlpha
    readonly property real faintTextAlpha: 0.4
    property bool reduceMotion: false
    property var windowMoveAnimation: ({ duration: 0, curve: [] })
    function duration(milliseconds) { return reduceMotion ? 0 : milliseconds }
    readonly property int hoverDuration: duration(180)
    readonly property int tooltipDelay: 400
    readonly property int focusPrimeDelay: 150
    readonly property int confirmationShownMs: 1400

    readonly property int defaultTextSize: popupStyle.defaultTextSize
    property int textSize: defaultTextSize
    readonly property real uiScale: textSize / defaultTextSize
    readonly property real glyphOvershoot: 0.15
    function px(size) { return Math.round(size * uiScale) }
    function fontPx(nominalSize) { return Math.round(nominalSize * textSize / defaultTextSize) }
    function typePx(ratio) { return Math.max(1, Math.round(textSize * ratio)) }
    function taskbarButtonWidth(iconSize, box) {
        return Math.max(px(24), iconSize + box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3]
            + 2 * Math.max(box.borderWidth, box.borderBottomWidth || 0))
    }
    function taskbarIconOffset(box, highlightLabels) {
        return (box.margin[0] - box.margin[2] + (highlightLabels ? 0 : box.padding[0] - box.padding[2])) / 2
    }

    property Process animationProbe: Process {
        command: ["hyprctl", "-j", "--batch", "getoption animations:enabled ; animations"]
        running: true
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const [setting, [animations, curves]] = text.trim().split(/\n\s*\n/).map(chunk => JSON.parse(chunk))
                const animation = ["windowsMove", "windows", "global"].map(name => animations.find(item => item.name === name)).find(item => item.overridden)
                const curve = curves.find(item => item.name === animation.bezier)
                const millisecondsPerDecisecond = 100
                root.reduceMotion = setting.bool === false
                root.windowMoveAnimation = { duration: animation.enabled ? animation.speed * millisecondsPerDecisecond : 0,
                    curve: [curve.X0, curve.Y0, curve.X1, curve.Y1, 1, 1] }
            }
            catch (error) { console.warn("animation setting: " + error) }
        } }
    }
    property Connections animationEvents: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && !root.animationProbe.running) root.animationProbe.running = true
        }
    }

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
            root.textSize = match ? parseInt(match[1]) : root.defaultTextSize
        }
    }
}

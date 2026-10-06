pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var shell
    required property bool playing
    required property int barCount
    required property int frameRate
    required property int smoothing
    required property real gain
    required property real barWidth
    required property real gap
    required property string position
    required property string mode
    readonly property string profile: JSON.stringify({ bars: barCount, fps: frameRate, smoothing: smoothing })
    readonly property var levels: (Cava.values[profile] ?? []).map(value => Math.max(0, Math.min(1, value * gain)))
    readonly property bool centered: mode === "mirror" || position === "center"
    readonly property var directions: centered ? [-1, 1] : position === "top" ? [1] : [-1]
    readonly property real originY: centered ? height / 2 : position === "top" ? 0 : height
    readonly property real extent: centered ? height / 2 : height
    readonly property real stride: barWidth + gap
    readonly property real pixel: Style.px(1)
    readonly property int blockCount: 4
    readonly property int peakHoldMs: 320
    readonly property real peakFallPerSecond: 1.56
    property var peaks: []
    property real frameTime: 0
    implicitWidth: barCount * stride - gap
    clip: true

    Component.onCompleted: Cava.consumers = Cava.consumers.concat([root])
    Component.onDestruction: Cava.consumers = Cava.consumers.filter(consumer => consumer !== root)
    onLevelsChanged: updatePeaks()
    onModeChanged: { peaks = []; frameTime = 0; updatePeaks() }

    function updatePeaks() {
        if (mode !== "foobar") return
        const now = Date.now()
        peaks = levels.map((level, index) => {
            const peak = peaks[index]
            return !peak || level >= peak.level ? { level: level, until: now + peakHoldMs }
                : { level: Math.max(level, peak.level - Math.max(0, now - Math.max(frameTime, peak.until))
                    * peakFallPerSecond / 1000), until: peak.until }
        })
        frameTime = now
    }

    Repeater {
        model: root.barCount * root.directions.length
        delegate: Item {
            id: band
            required property int index
            readonly property int bandIndex: Math.floor(index / root.directions.length)
            readonly property int direction: root.directions[index % root.directions.length]
            readonly property real level: root.levels[bandIndex] ?? 0
            readonly property real nextLevel: root.levels[bandIndex + 1] ?? level
            readonly property color color: direction < 0 ? root.shell.accent : root.shell.role("c6", root.shell.foreground)
            x: bandIndex * root.stride
            y: root.originY
            width: root.barWidth; height: root.extent
            transform: Scale { yScale: band.direction }

            Repeater {
                model: root.mode === "blocks" ? root.blockCount : 1
                delegate: Rectangle {
                    id: piece
                    required property int index
                    readonly property bool dot: root.mode === "dots"
                    readonly property bool wave: root.mode === "wave"
                    readonly property bool block: root.mode === "blocks"
                    x: wave ? band.width / 2 : 0
                    y: dot ? Math.max(0, Math.min(root.extent - height, band.level * root.extent - height / 2))
                        : wave ? band.level * root.extent - height / 2 : block ? index * (height + root.pixel) : 0
                    width: wave ? Math.hypot(root.stride, (band.nextLevel - band.level) * root.extent) : band.width
                    height: dot ? band.width : wave ? root.pixel
                        : block ? Math.max(0, (root.extent - (root.blockCount - 1) * root.pixel) / root.blockCount)
                        : Math.max(root.pixel / root.directions.length, band.level * root.extent)
                    visible: block ? index < Math.ceil(band.level * root.blockCount)
                        : !wave || band.bandIndex < root.barCount - 1
                    color: band.color
                    radius: dot ? width / 2 : 0
                    rotation: wave ? Math.atan2((band.nextLevel - band.level) * root.extent, root.stride) * 180 / Math.PI : 0
                    transformOrigin: Item.Left
                    antialiasing: dot || wave
                }
            }
            Loader {
                active: root.mode === "foobar"
                width: band.width; height: root.pixel
                y: Math.max(0, (root.peaks[band.bandIndex]?.level ?? 0) * root.extent - height)
                sourceComponent: Rectangle {
                    color: root.shell.role("error", root.shell.foreground)
                }
            }
        }
    }
}

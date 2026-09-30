import QtQuick

Canvas {
    id: root
    required property string glyph
    required property string family
    readonly property int probeSize: 64
    property rect ink: Qt.rect(0, 0, 0, 0)
    width: probeSize * 2; height: probeSize * 2; opacity: 0
    onGlyphChanged: requestPaint()
    onFamilyChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d"), originX = probeSize / 2, baseline = probeSize * 1.5
        ctx.reset(); ctx.font = probeSize + "px '" + family + "'"; ctx.fillStyle = "white"; ctx.fillText(glyph, originX, baseline)
        const pixels = ctx.getImageData(0, 0, width, height).data
        let left = width, right = -1, top = height, bottom = -1
        for (let y = 0; y < height; y++) for (let x = 0; x < width; x++)
            if (pixels[(y * width + x) * 4 + 3] > 96) { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y) }
        ink = right < 0 ? Qt.rect(0, 0, 0, 0)
            : Qt.rect((left - originX) / probeSize, (top - baseline) / probeSize, (right - left + 1) / probeSize, (bottom - top + 1) / probeSize)
    }
}

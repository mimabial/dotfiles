import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell

Item {
    id: root
    required property string name
    required property color color
    required property int size
    property string context: "status"
    property string directory: ""
    readonly property bool loaded: iconImage.status === Image.Ready
    readonly property int rasterSize: size * 2
    readonly property rect ink: Qt.rect(inkBoundsCanvas.ink.x * size, inkBoundsCanvas.ink.y * size, inkBoundsCanvas.ink.width * size, inkBoundsCanvas.ink.height * size)
    readonly property string iconName: name.includes("/") ? name.split("/")[1] : name
    readonly property string contextDirectory: (directory || "MacTahoe-dark/{context}/symbolic").replace("{context}", name.includes("/") ? name.split("/")[0] : context)
    readonly property string iconPath: (contextDirectory.startsWith("/") ? "" : Quickshell.env("HOME") + "/.local/share/icons/")
        + contextDirectory + "/" + iconName + "-symbolic.svg"
    implicitWidth: size; implicitHeight: size
    Image {
        id: iconImage
        anchors.fill: parent
        visible: false
        sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        source: root.iconName ? root.iconPath : ""
    }
    ColorOverlay {
        anchors.fill: parent
        source: iconImage
        color: root.color
    }
    Canvas {
        id: inkBoundsCanvas
        width: root.rasterSize; height: width; opacity: 0
        property rect ink: Qt.rect(0, 0, 1, 1)
        readonly property string imageSource: root.loaded ? root.iconPath : ""
        property string loadedSource: ""
        function load() {
            if (loadedSource) unloadImage(loadedSource)
            loadedSource = imageSource; ink = Qt.rect(0, 0, 1, 1)
            if (imageSource) loadImage(imageSource, Qt.size(width, height))
            requestPaint()
        }
        onImageSourceChanged: load()
        onWidthChanged: load()
        onImageLoaded: requestPaint()
        onPaint: {
            if (!imageSource || !isImageLoaded(imageSource)) return
            const canvas = getContext("2d")
            canvas.reset(); canvas.drawImage(imageSource, 0, 0, width, height)
            const pixels = canvas.getImageData(0, 0, width, height).data
            let left = width, right = -1, top = height, bottom = -1
            for (let y = 0; y < height; y++) for (let x = 0; x < width; x++)
                if (pixels[(y * width + x) * 4 + 3] > 0) { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y) }
            ink = right < 0 ? Qt.rect(0, 0, 0, 0)
                : Qt.rect(left / width, top / height, (right - left + 1) / width, (bottom - top + 1) / height)
        }
    }
}

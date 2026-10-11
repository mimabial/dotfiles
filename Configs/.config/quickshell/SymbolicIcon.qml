import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property string name
    required property color color
    required property int size
    property string context: "status"
    // icon themes disagree on where the context folder sits, so a style names
    // the whole path with {context} standing in for it
    property string directory: ""
    property string svg: ""
    readonly property bool loaded: svg !== ""
    readonly property int rasterSize: size * 2
    readonly property rect ink: Qt.rect(probe.ink.x * size, probe.ink.y * size, probe.ink.width * size, probe.ink.height * size)
    readonly property string iconName: name.includes("/") ? name.split("/")[1] : name
    readonly property string contextDirectory: (directory || "MacTahoe-dark/{context}/symbolic").replace("{context}", name.includes("/") ? name.split("/")[0] : context)
    implicitWidth: size; implicitHeight: size
    FileView {
        path: (root.contextDirectory.startsWith("/") ? "" : Quickshell.env("HOME") + "/.local/share/icons/")
            + root.contextDirectory + "/" + root.iconName + "-symbolic.svg"
        printErrors: false
        onLoaded: root.svg = text()
        onLoadFailed: root.svg = ""
    }
    Image {
        anchors.fill: parent; opacity: root.color.a
        sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        source: root.svg ? "data:image/svg+xml;utf8," + encodeURIComponent(root.svg.replace(/#[0-9a-fA-F]{6}\b/g, String(Qt.rgba(root.color.r, root.color.g, root.color.b, 1)))) : ""
    }
    Canvas {
        id: probe
        width: root.rasterSize; height: width; opacity: 0
        property rect ink: Qt.rect(0, 0, 1, 1)
        readonly property string imageSource: root.svg ? "data:image/svg+xml;utf8," + encodeURIComponent(root.svg) : ""
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
            const ctx = getContext("2d")
            ctx.reset(); ctx.drawImage(imageSource, 0, 0, width, height)
            const pixels = ctx.getImageData(0, 0, width, height).data
            let left = width, right = -1, top = height, bottom = -1
            for (let y = 0; y < height; y++) for (let x = 0; x < width; x++)
                if (pixels[(y * width + x) * 4 + 3] > 0) { left = Math.min(left, x); right = Math.max(right, x); top = Math.min(top, y); bottom = Math.max(bottom, y) }
            ink = right < 0 ? Qt.rect(0, 0, 0, 0)
                : Qt.rect(left / width, top / height, (right - left + 1) / width, (bottom - top + 1) / height)
        }
    }
}

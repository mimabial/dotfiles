pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
    id: canvas
    required property var layout
    required property var cmdText
    required property string screenName
    required property real nativeWidth
    required property real nativeHeight
    readonly property real scaleX: width / nativeWidth
    readonly property real scaleY: height / nativeHeight
    readonly property real scaleFactor: Math.min(scaleX, scaleY)
    clip: true

    function xy(value) {
        return Qt.point(value.xp ? value.x / 100 * canvas.width : value.x * canvas.scaleX,
                        value.yp ? value.y / 100 * canvas.height : value.y * canvas.scaleY)
    }
    function radius(w, h, rounding, thickness) {
        const half = Math.min(w, h) / 2
        if (rounding === -1)
            return half
        return rounding === 0 ? 0 : Math.max(0, Math.min(rounding * canvas.scaleFactor + thickness, half))
    }
    // Port of hyprlock's IWidget::posFromHVAlign, whose origin is bottom-left.
    function place(spec, w, h) {
        const a = spec.rotate * Math.PI / 180
        const rx = (w - (w * Math.abs(Math.cos(a)) + h * Math.abs(Math.sin(a)))) / 2
        const ry = (h - (w * Math.abs(Math.sin(a)) + h * Math.abs(Math.cos(a)))) / 2
        const p = canvas.xy(spec.position)
        let x = p.x
        let y = p.y
        if (spec.halign === "center") x += canvas.width / 2 - w / 2
        else if (spec.halign === "left") x -= rx
        else if (spec.halign === "right") x += canvas.width - w + rx
        if (spec.valign === "center") y += canvas.height / 2 - h / 2
        else if (spec.valign === "top") y += canvas.height - h + ry
        else if (spec.valign === "bottom") y -= ry
        return Qt.point(x, canvas.height - y - h)
    }
    // Qt rich text ignores Pango's span attributes; carry over the size and colour ones.
    function qtMarkup(text) {
        return text.replace(/<span\b([^>]*)>/g, (tag, attrs) => {
            const css = []
            const size = /\bsize="(\d+)"/.exec(attrs)
            if (size)
                css.push("font-size:" + Math.max(1, Number(size[1]) / 1024 * 4 / 3 * canvas.scaleFactor).toFixed(1) + "px")
            const colour = /\b(?:foreground|color)=["'](#[0-9A-Fa-f]{6})/.exec(attrs)
            if (colour)
                css.push("color:" + colour[1])
            return css.length ? '<span style="' + css.join(";") + '">' : "<span>"
        })
    }
    function label(value) {
        const shown = typeof value === "string" ? value : (canvas.cmdText[value.cmd] ?? "")
        return canvas.qtMarkup(shown).replace(/\n/g, "<br>")
    }
    // pango sizes are points rendered at 96 dpi
    function fontPx(points) {
        return Math.max(1, Math.round(points * 4 / 3 * canvas.scaleFactor))
    }

    Repeater {
        model: (canvas.layout?.widgets ?? []).filter(w => !w.monitor || w.monitor === canvas.screenName)

        delegate: Item {
            id: widget
            required property var modelData
            readonly property var spec: modelData
            readonly property point at: spec.type === "background" ? Qt.point(0, 0)
                                                                   : canvas.place(spec, width, height)
            x: at.x
            y: at.y
            z: spec.zindex
            width: loader.width
            height: loader.height
            rotation: -spec.rotate
            layer.enabled: spec.shadow_passes > 0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: widget.spec.shadow_color
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                shadowBlur: 1
                blurMax: Math.max(1, Math.round(Math.min(64, widget.spec.shadow_size * Math.pow(2, widget.spec.shadow_passes)) * canvas.scaleFactor))
            }

            Loader {
                id: loader
                sourceComponent: ({ background: backgroundBody, label: labelBody, image: imageBody,
                                    shape: shapeBody, "input-field": fieldBody })[widget.spec.type]
            }

            Component {
                id: backgroundBody
                Rectangle {
                    width: canvas.width
                    height: canvas.height
                    color: widget.spec.color
                    Image {
                        anchors.fill: parent
                        source: widget.spec.path ? "file://" + widget.spec.path : ""
                        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        layer.enabled: widget.spec.blur_passes > 0
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 1
                            blurMax: Math.max(1, Math.round(Math.min(64, widget.spec.blur_size * Math.pow(2, widget.spec.blur_passes)) * canvas.scaleFactor))
                            brightness: widget.spec.brightness - 1
                            contrast: widget.spec.contrast - 1
                        }
                    }
                }
            }

            Component {
                id: labelBody
                Text {
                    text: canvas.label(widget.spec.text)
                    textFormat: Text.RichText
                    color: widget.spec.color
                    font.family: widget.spec.font_family.family
                    font.weight: widget.spec.font_family.weight
                    font.italic: widget.spec.font_family.italic
                    font.pixelSize: canvas.fontPx(widget.spec.font_size)
                    horizontalAlignment: widget.spec.text_align === "center" ? Text.AlignHCenter
                                       : widget.spec.text_align === "right" ? Text.AlignRight
                                       : Text.AlignLeft
                }
            }

            Component {
                id: imageBody
                Rectangle {
                    readonly property real borderSize: widget.spec.border_size * canvas.scaleFactor
                    readonly property real fit: pic.implicitWidth > 0
                        ? widget.spec.size * canvas.scaleFactor / Math.min(pic.implicitWidth, pic.implicitHeight) : 0
                    visible: pic.status === Image.Ready
                    width: pic.implicitWidth * fit + 2 * borderSize
                    height: pic.implicitHeight * fit + 2 * borderSize
                    radius: canvas.radius(width, height, widget.spec.rounding, borderSize)
                    // hyprlock draws the border as a ring; a fill would show through a transparent image.
                    color: "transparent"
                    border.width: borderSize
                    border.color: widget.spec.border_color
                    Image {
                        id: pic
                        anchors.fill: parent
                        anchors.margins: parent.borderSize
                        source: widget.spec.path ? "file://" + widget.spec.path : ""
                        asynchronous: true
                        cache: false
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: picMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }
                    }
                    Rectangle {
                        id: picMask
                        anchors.fill: pic
                        radius: canvas.radius(width, height, widget.spec.rounding, 0)
                        color: "black"
                        visible: false
                        layer.enabled: true
                        layer.smooth: true
                    }
                }
            }

            Component {
                id: shapeBody
                Rectangle {
                    readonly property point inner: canvas.xy(widget.spec.size)
                    readonly property real borderSize: widget.spec.border_size * canvas.scaleFactor
                    width: inner.x + 2 * borderSize
                    height: inner.y + 2 * borderSize
                    radius: canvas.radius(width, height, widget.spec.rounding, borderSize)
                    color: widget.spec.xray ? "transparent" : widget.spec.color
                    border.width: borderSize
                    border.color: widget.spec.border_color
                }
            }

            Component {
                id: fieldBody
                Item {
                    id: field
                    readonly property point box: canvas.xy(widget.spec.size)
                    readonly property real ring: widget.spec.outline_thickness * canvas.scaleFactor
                    width: box.x
                    height: box.y
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -field.ring
                        visible: field.ring > 0
                        radius: canvas.radius(width, height, widget.spec.rounding, field.ring)
                        color: "transparent"
                        border.width: field.ring
                        border.color: widget.spec.outer_color
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: canvas.radius(width, height, widget.spec.rounding, 0)
                        color: widget.spec.inner_color
                    }
                    Text {
                        anchors.centerIn: parent
                        text: canvas.label(widget.spec.placeholder_text)
                        textFormat: Text.RichText
                        color: widget.spec.font_color
                        font.family: widget.spec.font_family.family
                        font.weight: widget.spec.font_family.weight
                        font.italic: widget.spec.font_family.italic
                        font.pixelSize: Math.max(1, Math.round(field.height / 3))
                    }
                }
            }
        }
    }
}

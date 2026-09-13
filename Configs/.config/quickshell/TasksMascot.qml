pragma ComponentBehavior: Bound

import QtQuick

// Adapted from Saikomantisu/omarchy-todos Mascot.qml; see THIRD_PARTY_LICENSES.md.
Item {
    id: root
    property real urgency: 0
    property real smile: .2
    property string eyes: "flat"
    property real brow: 0
    property int sweat: 0
    property int sparkle: 0
    property bool wavy: false
    required property real cornerRadius
    property color baseColor: "#cacccc"
    property color alertColor: "#a55555"
    property bool animated: true
    property bool blinking: false

    readonly property color inkColor: Qt.tint(baseColor,
        Qt.rgba(alertColor.r, alertColor.g, alertColor.b, Math.min(.9, urgency * .95)))
    readonly property string paintKey: [urgency, smile, eyes, brow, sweat, sparkle,
        wavy, blinking, cornerRadius, String(inkColor)].join("|")
    onPaintKeyChanged: face.requestPaint()
    implicitWidth: 22; implicitHeight: 22

    Timer {
        interval: 3500; repeat: true
        running: root.animated && root.visible && root.eyes !== "happy" && root.eyes !== "flat"
        onTriggered: { root.blinking = true; blinkHold.restart(); interval = 2600 + Math.random() * 4200 }
    }
    Timer { id: blinkHold; interval: 120; onTriggered: root.blinking = false }
    SequentialAnimation on rotation {
        running: root.animated && root.visible && root.urgency > .6
        loops: Animation.Infinite; alwaysRunToEnd: true
        NumberAnimation { from: 0; to: -3; duration: 130 }
        NumberAnimation { from: -3; to: 3; duration: 260 }
        NumberAnimation { from: 3; to: 0; duration: 130 }
        PauseAnimation { duration: 2400 }
    }

    Canvas {
        id: face
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d")
            const s = Math.min(width, height)
            if (s <= 0) return
            const u = value => value * s
            const ink = root.inkColor
            const stroke = Math.max(1, s * .085)
            const eyeY = u(.5)
            const eyeXs = [u(.325), u(.675)]
            const eyeShape = root.blinking && root.eyes !== "happy" ? "flat" : root.eyes
            function roundedRect(x, y, w, h, radius) {
                ctx.beginPath(); ctx.moveTo(x + radius, y); ctx.lineTo(x + w - radius, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
                ctx.lineTo(x + w, y + h - radius)
                ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
                ctx.lineTo(x + radius, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
                ctx.lineTo(x, y + radius); ctx.quadraticCurveTo(x, y, x + radius, y); ctx.closePath()
            }
            function star(x, y, radius) {
                ctx.beginPath(); ctx.moveTo(x, y - radius)
                ctx.quadraticCurveTo(x + radius * .2, y - radius * .2, x + radius, y)
                ctx.quadraticCurveTo(x + radius * .2, y + radius * .2, x, y + radius)
                ctx.quadraticCurveTo(x - radius * .2, y + radius * .2, x - radius, y)
                ctx.quadraticCurveTo(x - radius * .2, y - radius * .2, x, y - radius); ctx.fill()
            }
            function drop(x, y, radius) {
                ctx.beginPath(); ctx.arc(x, y, radius, 0, Math.PI * 2); ctx.fill()
                ctx.beginPath(); ctx.moveTo(x - radius * .62, y - radius * .78)
                ctx.lineTo(x, y - radius * 2.3); ctx.lineTo(x + radius * .62, y - radius * .78)
                ctx.closePath(); ctx.fill()
            }

            ctx.reset(); ctx.clearRect(0, 0, width, height)
            ctx.translate((width - s) / 2, (height - s) / 2)
            ctx.lineCap = "round"; ctx.lineJoin = "round"
            ctx.fillStyle = ink; ctx.strokeStyle = ink
            roundedRect(u(.05), u(.15), u(.9), u(.82),
                Math.min(u(.41), Math.max(0, root.cornerRadius))); ctx.fill()
            if (root.sparkle > 0) star(u(.895), u(.085), u(.075))
            if (root.sparkle > 1 && s >= 20) star(u(.115), u(.07), u(.052))

            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "#000"; ctx.strokeStyle = "#000"; ctx.lineWidth = stroke
            for (let index = 0; index < 2; index++) {
                const x = eyeXs[index]
                ctx.beginPath()
                if (eyeShape === "flat") { ctx.moveTo(x - u(.085), eyeY); ctx.lineTo(x + u(.085), eyeY); ctx.stroke() }
                else if (eyeShape === "happy") {
                    ctx.moveTo(x - u(.095), eyeY + u(.04)); ctx.quadraticCurveTo(x, eyeY - u(.115), x + u(.095), eyeY + u(.04)); ctx.stroke()
                } else { ctx.arc(x, eyeY, u(eyeShape === "wide" ? .115 : .09), 0, Math.PI * 2); ctx.fill() }
            }
            if (s >= 17 && root.brow > .05) {
                const lift = u(.06) * root.brow, fall = u(.04) * root.brow, y = u(.315)
                ctx.lineWidth = Math.max(1, s * .07)
                ctx.beginPath(); ctx.moveTo(u(.185), y + fall); ctx.lineTo(u(.425), y - lift); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(u(.815), y + fall); ctx.lineTo(u(.575), y - lift); ctx.stroke()
            }
            ctx.lineWidth = stroke; ctx.beginPath(); ctx.moveTo(u(.33), u(.745))
            if (root.wavy)
                for (let i = 1; i <= 3; i++) ctx.quadraticCurveTo(u(.33 + .113 * (i - .5)), u(.745 + (i % 2 ? -.06 : .06)), u(.33 + .113 * i), u(.745))
            else ctx.quadraticCurveTo(u(.5), u(.745 + .24 * root.smile), u(.67), u(.745))
            ctx.stroke()
            if (s >= 17 && root.sweat > 0) drop(u(.845), u(.305), u(.05))
            if (s >= 17 && root.sweat > 1) drop(u(.155), u(.275), u(.044))
            if (eyeShape === "wide") {
                ctx.globalCompositeOperation = "source-over"; ctx.fillStyle = ink
                for (let i = 0; i < 2; i++) { ctx.beginPath(); ctx.arc(eyeXs[i], eyeY + u(.012), u(.045), 0, Math.PI * 2); ctx.fill() }
            }
        }
    }
}

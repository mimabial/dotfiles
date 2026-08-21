import QtQuick

BarSlider {
    id: root
    css: "backlight-slider"
    from: .05

    // Backlight is the source of truth, but it only learns of a change after
    // the write lands; until then the dragged value wins so the handle does
    // not snap back under the cursor
    property int pending: -1
    value: (pending >= 0 ? pending : Backlight.percent) / 100
    onMoved: fraction => { pending = Math.round(fraction * 100); apply.restart() }

    Timer {
        id: apply; interval: 50
        onTriggered: { root.shell.run(["brightnessctl", "set", root.pending + "%"]); Backlight.nudge() }
    }
    // hand control back as soon as the singleton agrees with what we asked for
    Connections {
        target: Backlight
        function onPercentChanged() {
            if (root.pending >= 0 && Math.abs(Backlight.percent - root.pending) <= 1) root.pending = -1
        }
    }
    // ... or if the write never took effect
    Timer { running: root.pending >= 0; interval: 2000; onTriggered: root.pending = -1 }
}

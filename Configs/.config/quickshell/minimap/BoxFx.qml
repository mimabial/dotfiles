pragma ComponentBehavior: Bound
import QtQuick
import qs

Item {
    id: fx
    required property var shell
    property string style: "smooth"
    property int level: 0
    property color fill: accent
    property real corner: 0
    readonly property real unit: Style.uiScale
    readonly property color accent: shell.accent
    readonly property color warn: shell.role("warning", shell.accent)
    readonly property color urgent: shell.role("error", shell.accent)
    readonly property color glitchCyan: shell.role("c6", shell.accent)
    readonly property color glitchMagenta: shell.role("c5", shell.accent)
    readonly property color tone: level >= 2 ? urgent : level === 1 ? warn : accent
    readonly property real power: level >= 2 ? 1 : 0.6
    property real flick: 1
    property real pulse: 0
    property real gx: 0
    property real tearY1: 0
    property real tearY2: 0
    property real tearDx1: 0
    property real tearDx2: 0
    anchors.fill: parent

    function play(kind) {
        if (Style.reduceMotion) return
        if (kind === "resolve") flashAt(0.8, 420, accent)
        if (style === "cyberpunk") glitchAnim.restart()
    }
    function attend() {
        if (Style.reduceMotion) return
        if (style === "cyberpunk") { glitchAnim.restart(); flashAt(0.5 * power, 260, tone) }
        else flashAt(0.55 * power, level >= 2 ? 600 : 1100, tone)
    }
    function flashAt(peak, duration, color) {
        flashRect.color = color
        flashAnim.peak = peak
        flashAnim.duration = duration
        flashAnim.restart()
    }
    function reTear(on) {
        const side = () => Math.random() < 0.5 ? -1 : 1
        tearY1 = Math.random() * Math.max(1, height - 2 * unit)
        tearY2 = Math.random() * Math.max(1, height - 2 * unit)
        tearDx1 = on ? side() * (3 + Math.random() * 6) * unit : 0
        tearDx2 = on ? side() * (2 + Math.random() * 5) * unit : 0
    }

    Connections {
        target: Style
        function onReduceMotionChanged() { if (Style.reduceMotion) { flashAnim.complete(); glitchAnim.stop() } }
    }
    Timer {
        interval: fx.level >= 2 ? 900 : 2200
        repeat: true
        running: !Style.reduceMotion && fx.level > 0 && fx.visible
        triggeredOnStart: true
        onTriggered: fx.attend()
    }
    SequentialAnimation on pulse {
        running: !Style.reduceMotion && fx.level > 0 && fx.visible
        loops: Animation.Infinite
        onStopped: fx.pulse = 0
        NumberAnimation { to: 1; duration: fx.level >= 2 ? 420 : 1100; easing.type: fx.style === "cyberpunk" ? Easing.Linear : Easing.InOutSine }
        NumberAnimation { to: 0; duration: fx.level >= 2 ? 420 : 1100; easing.type: fx.style === "cyberpunk" ? Easing.Linear : Easing.InOutSine }
    }
    Repeater {
        model: 3
        Rectangle {
            required property int index
            readonly property real spread: (1.2 + index * 1.5) * fx.unit
            anchors.fill: parent
            anchors.margins: -spread
            radius: fx.corner + spread
            color: "transparent"
            border.width: 1.6 * fx.unit
            border.color: fx.tone
            opacity: fx.level > 0 ? (fx.level >= 2 ? 0.9 : 0.6) * (0.35 + 0.65 * fx.pulse) / (1 + index * 1.1) : 0
            MotionBehavior on opacity { NumberAnimation { duration: 200 } }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: fx.corner
        color: "transparent"
        border.width: fx.unit
        border.color: fx.tone
        opacity: fx.level >= 2 ? 0.95 : fx.level === 1 ? 0.55 : 0
        MotionBehavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutSine } }
        MotionBehavior on border.color { ColorAnimation { duration: 260 } }
    }
    Rectangle { id: flashRect; anchors.fill: parent; radius: fx.corner; opacity: 0 }
    SequentialAnimation {
        id: flashAnim
        property real peak: 0.6
        property int duration: 500
        NumberAnimation { target: flashRect; property: "opacity"; to: flashAnim.peak; duration: Math.max(60, flashAnim.duration * 0.25); easing.type: Easing.OutSine }
        NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: flashAnim.duration * 0.75; easing.type: Easing.InOutSine }
    }
    Rectangle {
        z: -1
        x: fx.gx
        width: fx.width; height: fx.height; radius: fx.corner
        color: fx.glitchCyan
        opacity: fx.gx !== 0 ? 0.75 : 0
    }
    Rectangle {
        z: -1
        x: -fx.gx; y: fx.gx !== 0 ? fx.unit : 0
        width: fx.width; height: fx.height; radius: fx.corner
        color: fx.glitchMagenta
        opacity: fx.gx !== 0 ? 0.75 : 0
    }
    Rectangle { x: fx.tearDx1; y: fx.tearY1; width: fx.width; height: 2 * fx.unit; color: fx.fill; visible: fx.tearDx1 !== 0 }
    Rectangle { x: fx.tearDx2; y: fx.tearY2; width: fx.width; height: 1.5 * fx.unit; color: fx.fill; visible: fx.tearDx2 !== 0 }
    SequentialAnimation {
        id: glitchAnim
        onStopped: { fx.gx = 0; fx.flick = 1; fx.reTear(false) }
        ScriptAction { script: { fx.gx = 3 * fx.unit; fx.flick = 0.3; fx.reTear(true) } }
        PauseAnimation { duration: 45 }
        ScriptAction { script: { fx.gx = -3 * fx.unit; fx.flick = 1; fx.reTear(true) } }
        PauseAnimation { duration: 40 }
        ScriptAction { script: { fx.gx = 2 * fx.unit; fx.flick = 0.5; fx.reTear(true) } }
        PauseAnimation { duration: 55 }
        ScriptAction { script: { fx.gx = -2 * fx.unit; fx.flick = 1; fx.reTear(true) } }
        PauseAnimation { duration: 40 }
        ScriptAction { script: { fx.gx = fx.unit; fx.flick = 0.7; fx.reTear(true) } }
        PauseAnimation { duration: 40 }
    }
}

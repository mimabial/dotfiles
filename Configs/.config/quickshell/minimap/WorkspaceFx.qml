pragma ComponentBehavior: Bound
import QtQuick
import qs

Item {
    id: wf
    required property var shell
    property Item source: null
    property string style: "smooth"
    readonly property real unit: Style.uiScale
    readonly property color accent: shell.accent
    property bool tearing: false
    property var strips: []

    function play() {
        if (!source || Style.reduceMotion) return
        if (style === "cyberpunk") { tearAnim.restart(); scanAnim.restart(); fringeAnim.restart() }
        else dipAnim.restart()
    }
    function reroll(amount) {
        strips = Array.from({ length: 3 + Math.floor(Math.random() * 3) }, () => {
            const height = (2 + Math.random() * Math.max(2, wf.height * 0.16)) * unit
            return { y: Math.random() * Math.max(1, wf.height - height), h: height,
                dx: (Math.random() < 0.5 ? -1 : 1) * (3 + Math.random() * amount) * unit }
        })
    }

    Connections {
        target: Style
        function onReduceMotionChanged() {
            if (Style.reduceMotion) { dipAnim.complete(); tearAnim.stop(); fringeAnim.stop(); scanAnim.stop() }
        }
    }
    SequentialAnimation {
        id: dipAnim
        NumberAnimation { target: wf.source; property: "opacity"; to: 0.65; duration: 120; easing.type: Easing.OutSine }
        NumberAnimation { target: wf.source; property: "opacity"; to: 1; duration: 320; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: tearAnim
        onStopped: { wf.tearing = false; wf.strips = [] }
        ScriptAction { script: { wf.tearing = true; wf.reroll(16) } }
        PauseAnimation { duration: 55 }
        ScriptAction { script: wf.reroll(10) }
        PauseAnimation { duration: 45 }
        ScriptAction { script: wf.reroll(22) }
        PauseAnimation { duration: 60 }
        ScriptAction { script: wf.reroll(8) }
        PauseAnimation { duration: 50 }
        ScriptAction { script: wf.reroll(4) }
        PauseAnimation { duration: 45 }
    }
    Repeater {
        model: wf.tearing ? wf.strips : []
        Item {
            required property var modelData
            y: modelData.y
            width: wf.width; height: modelData.h
            clip: true
            Rectangle { anchors.fill: parent; color: wf.shell.background }
            ShaderEffectSource {
                x: parent.modelData.dx
                width: wf.width; height: parent.height
                sourceItem: wf.source
                sourceRect: Qt.rect(0, parent.modelData.y, wf.width, parent.height)
                live: true
            }
        }
    }
    Rectangle { id: fringeCyan; width: wf.width; height: wf.height; color: wf.shell.role("c6", wf.accent); opacity: 0 }
    Rectangle { id: fringeMagenta; width: wf.width; height: wf.height; color: wf.shell.role("c5", wf.accent); opacity: 0 }
    SequentialAnimation {
        id: fringeAnim
        onStopped: { fringeCyan.opacity = 0; fringeMagenta.opacity = 0; fringeCyan.x = 0; fringeMagenta.x = 0 }
        ScriptAction { script: { fringeCyan.x = -2 * wf.unit; fringeMagenta.x = 2 * wf.unit; fringeCyan.opacity = 0.07; fringeMagenta.opacity = 0.07 } }
        PauseAnimation { duration: 90 }
        ScriptAction { script: { fringeCyan.x = 3 * wf.unit; fringeMagenta.x = -3 * wf.unit; fringeCyan.opacity = 0.04; fringeMagenta.opacity = 0.05 } }
        PauseAnimation { duration: 80 }
    }
    Rectangle { id: scan; width: wf.width; height: wf.unit; color: wf.shell.role("c14", wf.accent); opacity: 0 }
    SequentialAnimation {
        id: scanAnim
        onStopped: scan.opacity = 0
        ScriptAction { script: { scan.y = 0; scan.opacity = 0.9 } }
        NumberAnimation { target: scan; property: "y"; to: wf.height; duration: 240; easing.type: Easing.Linear }
    }
}

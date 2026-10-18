import QtQuick

Item {
    id: root

    property var ui: null
    property string key: ""
    property string opt: ""
    property bool on: false

    width: 64
    height: 34

    readonly property color ink: on ? ui.accent : ui.tint(0.55)
    readonly property color soft: on ? ui.accentTint(0.40) : ui.tint(0.20)

    Row {
        visible: root.key === "scope"
        anchors.centerIn: parent
        spacing: 3
        Repeater {
            model: 4
            Rectangle {
                width: 13; height: 18; radius: 2
                
                readonly property bool shown: root.opt === "all" || (root.opt === "others" && index !== 1)
                    || (root.opt === "monitor" && index < 2) || (root.opt === "workspace" && index === 1)
                color: shown ? root.ink : root.soft
                opacity: shown ? 1 : 0.5
                border.width: index === 1 ? 1 : 0
                border.color: root.ink
            }
        }
    }
}

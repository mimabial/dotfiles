pragma ComponentBehavior: Bound
import QtQuick

PopupCard {
    id: root
    popupName: "themerotation"
    contentWidth: Style.px(320)
    contentHeight: rotationColumn.implicitHeight + padding * 2
    readonly property var themeRotation: shell.themeRotation
    readonly property var steps: Wallpaper.intervalSteps

    Column {
        id: rotationColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero { shell: root.shell; title: "Theme rotation"; status: root.themeRotation.statusText }

        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "SCHEDULE"; value: root.shell.themeName }

            PopupToggleRow {
                width: parent.width; shell: root.shell
                icon: root.themeRotation.enabled ? "󰑖" : "󰑗"
                title: "Automatic switching"
                detail: root.themeRotation.enabled ? Wallpaper.intervalLabel(root.themeRotation.intervalMinutes) : "Paused"
                checked: root.themeRotation.enabled
                onToggled: root.themeRotation.setEnabled(!root.themeRotation.enabled)
            }

            PopupSlider {
                id: intervalSlider
                width: parent.width; shell: root.shell
                label: "Interval"
                value: root.steps.indexOf(root.themeRotation.intervalMinutes)
                maximum: root.steps.length - 1
                step: 1
                tickCount: root.steps.length
                valueText: Wallpaper.intervalLabel(root.steps[Math.round(intervalSlider.liveValue)])
                onReleased: value => root.themeRotation.save({intervalMinutes: root.steps[Math.round(value)]})
            }

            Row {
                width: parent.width; spacing: Style.sm
                Repeater {
                    model: [{value: "next", label: "Sequential", icon: "󰒬"},
                            {value: "random", label: "Shuffle", icon: "󰒝"}]
                    PopupTab {
                        required property var modelData
                        width: (rotationColumn.width - Style.sm) / 2
                        shell: root.shell; icon: modelData.icon; text: modelData.label
                        selected: root.themeRotation.order === modelData.value
                        onClicked: root.themeRotation.save({order: modelData.value})
                    }
                }
            }

            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰑐"; title: "Switch theme now"
                onClicked: root.themeRotation.rotate()
            }

            Text {
                width: parent.width
                text: "Rotates among themes of the current polarity, dark with dark and light with light, "
                    + "so Auto color mode keeps its sunrise and sunset switch. Picking a theme restarts the interval."
                color: root.shell.faintText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                wrapMode: Text.WordWrap
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick

PopupCard {
    id: root
    popupName: "brightness"
    contentWidth: Style.px(320)
    contentHeight: column.implicitHeight + padding * 2
    property int draftPercent: -1
    onOpenChanged: if (!open) draftPercent = -1
    Connections { target: Backlight; function onPercentChanged() {
        if (Backlight.percent === root.draftPercent) root.draftPercent = -1
    } }

    Column {
        id: column
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.md
        PopupHero { shell: root.shell; title: "Brightness"; status: Backlight.percent + "%" }
        PopupSeparator { shell: root.shell }
        PopupSlider {
            width: parent.width; shell: root.shell
            label: "Brightness"; value: root.draftPercent >= 0 ? root.draftPercent : Backlight.percent
            minimum: 1; maximum: 100; step: 1
            valueText: Math.round(value) + "%"
            onChanged: percent => root.draftPercent = Math.round(percent)
            onReleased: percent => root.shell.run(["brightnessctl", "set", Math.round(percent) + "%"], Backlight.refresh)
        }
    }
}

import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var shell
    property string label: ""
    property string icon: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0
    property string valueText: Math.round(value * 100) + "%"
    signal changed(real value)
    signal released(real value)
    implicitHeight: labelText.implicitHeight + Style.md + Style.sliderHeight

    Text { id: labelText; anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.icon + (root.icon && root.label ? "  " : "") + root.label; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
    Text { anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.valueText; color: root.shell.alpha(root.shell.foreground, .65); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    Slider {
        id: slider
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        height: Style.sliderHeight
        from: root.minimum; to: root.maximum; value: root.value
        stepSize: root.step; snapMode: root.step > 0 ? Slider.SnapAlways : Slider.NoSnap
        onMoved: root.changed(value)
        onPressedChanged: if (!pressed) root.released(value)
        Binding on value { when: !slider.pressed; value: root.value; restoreMode: Binding.RestoreNone }
        background: Rectangle { implicitWidth: 100; implicitHeight: Style.trackHeight; x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - height / 2; width: parent.availableWidth; height: Style.trackHeight; radius: Style.trackHeight / 2; color: root.shell.alpha(root.shell.foreground, .14); Rectangle { width: parent.width * (parent.parent.value / parent.parent.to); height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) } }
        handle: Rectangle { implicitWidth: Style.knobSize; implicitHeight: Style.knobSize; x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width); y: parent.topPadding + parent.availableHeight / 2 - height / 2; width: Style.knobSize; height: Style.knobSize; radius: Style.knobSize / 2; color: root.shell.foreground }
    }
}

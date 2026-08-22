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
    // a slider under a PopupSection that already carries name and reading needs
    // neither, and then the header row collapses
    property int tickCount: 0
    readonly property bool headed: label !== "" || icon !== "" || valueText !== ""
    signal changed(real value)
    signal released(real value)
    implicitHeight: (headed ? labelText.implicitHeight + Style.md : 0) + Style.sliderHeight

    Text { id: labelText; visible: root.headed; anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.icon + (root.icon && root.label ? "  " : "") + root.label; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
    Text { visible: root.headed; anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.valueText; color: root.shell.alpha(root.shell.foreground, .65); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    Slider {
        id: slider
        // Controls take focus on click by default, which would pull it off the
        // surrounding card and kill its arrow-key navigation. The slider is
        // driven by the pointer, so it never needs the keyboard itself.
        focusPolicy: Qt.NoFocus
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        height: Style.sliderHeight
        from: root.minimum; to: root.maximum
        stepSize: root.step; snapMode: root.step > 0 ? Slider.SnapAlways : Slider.NoSnap
        onMoved: root.changed(value)
        onPressedChanged: if (!pressed) root.released(value)
        // Dragging assigns Slider.value directly, which is exactly what a
        // declarative binding to it cannot survive. Push the value in instead,
        // whenever the pointer is not holding the handle, so an external change
        // — a reset, a fresh reading — always moves it.
        Component.onCompleted: value = root.value
        Connections {
            target: root
            function onValueChanged() { if (!slider.pressed) slider.value = root.value }
        }
        background: Rectangle {
            implicitWidth: Style.px(100); implicitHeight: Style.trackHeight
            x: parent.leftPadding; y: parent.topPadding + parent.availableHeight / 2 - height / 2
            width: parent.availableWidth; height: Style.trackHeight; radius: Style.trackHeight / 2
            color: root.shell.alpha(root.shell.foreground, .14)
            Rectangle { width: parent.width * (parent.parent.value / parent.parent.to); height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) }
            // notches in the card colour, so a stepped slider reads as segments
            Repeater {
                model: root.tickCount > 1 ? root.tickCount : 0
                Rectangle {
                    required property int index
                    width: Math.max(1, Style.px(2)); height: parent.height + Style.px(4); radius: 1
                    color: root.shell.background
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * (index / (root.tickCount - 1)) - width / 2))
                }
            }
        }
        handle: Rectangle { implicitWidth: Style.knobSize; implicitHeight: Style.knobSize; x: parent.leftPadding + parent.visualPosition * (parent.availableWidth - width); y: parent.topPadding + parent.availableHeight / 2 - height / 2; width: Style.knobSize; height: Style.knobSize; radius: Style.knobSize / 2; color: root.shell.foreground }
    }
}

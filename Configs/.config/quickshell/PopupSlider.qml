pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var shell
    property string label: ""
    property string icon: ""
    property real value: 0
    readonly property real liveValue: pointerSlider.value
    property real minimum: 0
    property real maximum: 1
    property real step: 0
    property string valueText: Math.round(value * 100) + "%"
    property bool keyboardEnabled: true
    property bool keyboardAdjustsExternally: false
    readonly property bool navigable: keyboardEnabled && enabled
    property bool cursored: false
    property int tickCount: 0
    readonly property bool hasHeader: label !== "" || icon !== "" || valueText !== ""
    signal changed(real value)
    signal released(real value)
    signal keyboardAdjusted(int direction)
    signal clicked(int button)
    implicitHeight: (hasHeader ? labelText.implicitHeight + Style.md : 0) + Style.sliderHeight

    function syncExternalValue() {
        if (!pointerSlider.pressed) pointerSlider.value = value
    }

    function adjustKeyboard(direction) {
        if (keyboardAdjustsExternally) {
            keyboardAdjusted(direction)
            return
        }
        const amount = step > 0 ? step : (maximum - minimum) / 20
        const next = Math.max(minimum, Math.min(maximum, value + amount * direction))
        changed(next)
        released(next)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -Style.xs
        anchors.bottomMargin: -Style.xs
        visible: root.cursored
        color: root.shell.hoverFill()
        border.color: root.shell.hoverEdge(.85)
        radius: root.shell.rounding
    }

    Text { id: labelText; visible: root.hasHeader; anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.icon + (root.icon && root.label ? "  " : "") + root.label; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
    Text { visible: root.hasHeader; anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.top: parent.top; text: root.valueText; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    Slider {
        id: pointerSlider
        focusPolicy: Qt.NoFocus
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        height: Style.sliderHeight
        from: root.minimum; to: root.maximum
        stepSize: root.step; snapMode: root.step > 0 ? Slider.SnapAlways : Slider.NoSnap
        onMoved: root.changed(value)
        onPressedChanged: if (!pressed) root.released(value)
        Component.onCompleted: root.syncExternalValue()
        Connections {
            target: root
            function onValueChanged() { root.syncExternalValue() }
        }
        background: Rectangle {
            implicitWidth: Style.px(100); implicitHeight: Style.trackHeight
            x: pointerSlider.leftPadding; y: pointerSlider.topPadding + pointerSlider.availableHeight / 2 - height / 2
            width: pointerSlider.availableWidth; height: Style.trackHeight; radius: Style.trackHeight / 2
            color: root.shell.alpha(root.shell.foreground, .14)
            Rectangle { width: parent.width * pointerSlider.visualPosition; height: parent.height; radius: parent.radius; color: root.shell.role("act_br", root.shell.accent) }
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
        handle: Rectangle { implicitWidth: Style.knobSize; implicitHeight: Style.knobSize; x: pointerSlider.leftPadding + pointerSlider.visualPosition * (pointerSlider.availableWidth - width); y: pointerSlider.topPadding + pointerSlider.availableHeight / 2 - height / 2; width: Style.knobSize; height: Style.knobSize; radius: Style.knobSize / 2; color: root.shell.foreground }
    }
    PopupPointer { shell: root.shell; row: root }
}

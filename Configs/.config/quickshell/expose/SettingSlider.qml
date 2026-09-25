pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: settingSlider
    required property var controller
    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    property string suffix: ""
    signal edited(real nextValue)
    signal committed(real nextValue)
    implicitWidth: Style.space(280)
    implicitHeight: Style.spacing.controlHeight
    activeFocusOnTab: true
    readonly property real span: Math.max(0.000001, to - from)
    readonly property real normalizedValue: Math.max(0, Math.min(1, (value - from) / span))

    function valueAt(position) {
        var availableWidth = Math.max(1, sliderTrackArea.width - sliderHandle.width);
        var normalized = Math.max(0, Math.min(1, (position - sliderHandle.width / 2) / availableWidth));
        var raw = settingSlider.from + normalized * settingSlider.span;
        if (settingSlider.stepSize <= 0)
            return raw;
        var stepped = settingSlider.from + Math.round((raw - settingSlider.from) / settingSlider.stepSize) * settingSlider.stepSize;
        return Math.max(settingSlider.from, Math.min(settingSlider.to, stepped));
    }

    function commitKeyboardValue(nextValue) {
        var next = Math.max(settingSlider.from, Math.min(settingSlider.to, nextValue));
        settingSlider.edited(next);
        settingSlider.committed(next);
    }

    Keys.onPressed: function (event) {
        if (settingSlider.controller.handleSettingsNavigation(event))
            return;
        if (event.key === Qt.Key_Left)
            settingSlider.commitKeyboardValue(settingSlider.value - settingSlider.stepSize);
        else if (event.key === Qt.Key_Right)
            settingSlider.commitKeyboardValue(settingSlider.value + settingSlider.stepSize);
        else if (event.key === Qt.Key_Home)
            settingSlider.commitKeyboardValue(settingSlider.from);
        else if (event.key === Qt.Key_End)
            settingSlider.commitKeyboardValue(settingSlider.to);
        else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    RowLayout {
        anchors.fill: parent
        spacing: Style.spacing.md

        Item {
            id: sliderTrackArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(2)
                color: Color.menu.border
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * settingSlider.normalizedValue
                height: Style.space(3)
                color: Color.accent
            }

            ThemedControl {
                id: sliderHandle
                width: Style.space(12)
                height: width
                x: Math.round((parent.width - width) * settingSlider.normalizedValue)
                anchors.verticalCenter: parent.verticalCenter
                focused: settingSlider.activeFocus
                hovered: sliderMouse.containsMouse
                pressed: sliderMouse.pressed
                color: stateColor
            }

            MouseArea {
                id: sliderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: function (mouse) {
                    settingSlider.forceActiveFocus();
                    settingSlider.edited(settingSlider.valueAt(mouse.x));
                }
                onPositionChanged: function (mouse) {
                    if (pressed)
                        settingSlider.edited(settingSlider.valueAt(mouse.x));
                }
                onReleased: function (mouse) {
                    settingSlider.committed(settingSlider.valueAt(mouse.x));
                }
            }
        }

        Text {
            Layout.preferredWidth: Style.space(52)
            horizontalAlignment: Text.AlignRight
            text: Math.round(settingSlider.value) + settingSlider.suffix
            textFormat: Text.PlainText
            color: sliderHandle.stateColor
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: settingSlider.activeFocus
        }
    }
}

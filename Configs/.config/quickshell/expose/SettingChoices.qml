pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Flow {
    id: settingChoices
    required property var controller
    property var options: []
    property string value: ""
    signal chosen(string nextValue)
    spacing: Style.spacing.md
    Layout.minimumWidth: 0
    activeFocusOnTab: true

    function chooseOffset(offset, wrap) {
        var count = settingChoices.options.length;
        if (!count)
            return;
        var current = 0;
        for (var index = 0; index < count; index++)
            if (String(settingChoices.options[index].value) === settingChoices.value)
                current = index;
        var next = wrap
            ? (current + offset + count) % count
            : Math.max(0, Math.min(count - 1, current + offset));
        if (next !== current)
            settingChoices.chosen(String(settingChoices.options[next].value));
    }

    Keys.onPressed: function (event) {
        if (settingChoices.controller.handleSettingsNavigation(event))
            return;
        if (event.key === Qt.Key_Left)
            settingChoices.chooseOffset(-1, false);
        else if (event.key === Qt.Key_Right)
            settingChoices.chooseOffset(1, false);
        else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            settingChoices.chooseOffset(1, true);
        else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    Repeater {
        model: settingChoices.options

        delegate: ThemedControl {
            id: choice
            required property var modelData
            selected: String(modelData.value) === settingChoices.value
            focused: settingChoices.activeFocus && selected
            hovered: choiceMouse.containsMouse
            pressed: choiceMouse.pressed
            width: choiceLabel.implicitWidth + Style.spacing.controlPaddingX * 2
            height: Math.max(Style.spacing.controlHeight, choiceLabel.implicitHeight + Style.spacing.controlPaddingY * 2)

            Text {
                id: choiceLabel
                anchors.centerIn: parent
                text: String(choice.modelData.label)
                textFormat: Text.PlainText
                color: choice.stateColor
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: choice.selected
            }

            MouseArea {
                id: choiceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    settingChoices.forceActiveFocus();
                    settingChoices.chosen(String(choice.modelData.value));
                }
            }
        }
    }
}

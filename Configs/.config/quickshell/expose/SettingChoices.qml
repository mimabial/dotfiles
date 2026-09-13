pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

RowLayout {
    id: settingChoices
    required property var controller
    property var options: []
    property string value: ""
    signal chosen(string nextValue)
    spacing: Style.spacing.lg
    activeFocusOnTab: true

    // Arrows stop at either end; Space/Enter cycle through every option.
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

        delegate: Item {
            id: choice
            required property var modelData
            readonly property bool selected: String(modelData.value) === settingChoices.value
            Layout.preferredWidth: choiceLabel.implicitWidth
            Layout.preferredHeight: Style.space(28)

            Text {
                id: choiceLabel
                anchors.centerIn: parent
                text: String(choice.modelData.label)
                textFormat: Text.PlainText
                color: choice.selected && settingChoices.activeFocus ? Color.accent : Color.menu.text
                opacity: choice.selected ? 1 : 0.45
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: choice.selected
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(2, Style.focusBorderWidth)
                visible: choice.selected
                color: Color.accent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    settingChoices.forceActiveFocus();
                    settingChoices.chosen(String(choice.modelData.value));
                }
            }
        }
    }
}

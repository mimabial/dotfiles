pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Item {
    id: settingToggle
    required property var controller
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: Style.space(72)
    implicitHeight: Style.space(28)
    activeFocusOnTab: true

    Keys.onPressed: function (event) {
        if (settingToggle.controller.handleSettingsNavigation(event))
            return;
        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
            event.accepted = false;
            return;
        }
        settingToggle.toggled(!settingToggle.checked);
        event.accepted = true;
    }

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: settingToggle.checked ? "On" : "Off"
        textFormat: Text.PlainText
        color: Color.menu.text
        opacity: settingToggle.checked ? 1 : 0.45
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
    }

    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: Style.space(14)
        color: "transparent"
        border.color: settingToggle.checked ? Color.accent : Color.menu.border
        border.width: Math.max(1, Style.normalBorderWidth)

        Rectangle {
            width: Style.space(10)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            x: settingToggle.checked ? parent.width - width - Style.space(2) : Style.space(2)
            color: settingToggle.checked ? Color.accent : Color.menu.text
            opacity: settingToggle.checked ? 1 : 0.45
            Behavior on x { NumberAnimation { duration: 100 } }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        visible: settingToggle.activeFocus
        color: "transparent"
        border.color: Color.accent
        border.width: Math.max(2, Style.focusBorderWidth)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: settingToggle.forceActiveFocus()
        onClicked: settingToggle.toggled(!settingToggle.checked)
    }
}

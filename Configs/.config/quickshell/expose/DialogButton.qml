pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Rectangle {
    id: dialogButton
    required property var controller
    property string label: ""
    property bool destructive: false
    property bool hovered: false
    signal clicked()
    implicitWidth: buttonLabel.implicitWidth + Style.space(28)
    implicitHeight: Style.space(36)
    activeFocusOnTab: true
    color: "transparent"
    border.color: enabled && (activeFocus || hovered || destructive) ? Color.accent : Color.menu.border
    border.width: activeFocus ? Math.max(2, Style.focusBorderWidth) : Math.max(1, Style.normalBorderWidth)
    opacity: enabled ? 1 : 0.38

    Keys.onPressed: function (event) {
        if (dialogButton.controller.handleSettingsNavigation(event))
            return;
        if (!enabled || (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)) {
            event.accepted = false;
            return;
        }
        dialogButton.clicked();
        event.accepted = true;
    }

    Text {
        id: buttonLabel
        anchors.centerIn: parent
        text: dialogButton.label
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: dialogButton.destructive
    }

    MouseArea {
        anchors.fill: parent
        enabled: dialogButton.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: dialogButton.hovered = true
        onExited: dialogButton.hovered = false
        onPressed: dialogButton.forceActiveFocus()
        onClicked: dialogButton.clicked()
    }
}

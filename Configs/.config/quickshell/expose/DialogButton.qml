pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

ThemedControl {
    id: dialogButton
    required property var controller
    property string label: ""
    property bool destructive: false
    signal clicked()
    implicitWidth: buttonLabel.implicitWidth + Style.spacing.controlPaddingX * 2
    implicitHeight: Math.max(Style.spacing.controlHeight, buttonLabel.implicitHeight + Style.spacing.controlPaddingY * 2)
    activeFocusOnTab: true
    focused: activeFocus
    pressed: buttonMouse.pressed
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
        color: dialogButton.destructive ? Color.urgent : dialogButton.stateColor
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: dialogButton.destructive
    }

    MouseArea {
        id: buttonMouse
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

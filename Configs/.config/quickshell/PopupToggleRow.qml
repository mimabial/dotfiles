pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    required property var shell
    property string icon: ""
    property string title: ""
    property string detail: ""
    property bool checked: false
    signal toggled
    implicitHeight: row.implicitHeight

    PopupRow {
        id: row
        anchors.fill: parent
        shell: root.shell
        icon: root.icon
        title: root.title
        detail: root.detail
        rightInset: toggle.width + Style.xs
        interactive: false
    }
    ToggleSwitch {
        id: toggle
        anchors.right: parent.right
        anchors.rightMargin: Style.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        shell: root.shell
        checked: root.checked
        keyboardEnabled: true
        onToggled: root.toggled()
    }
}

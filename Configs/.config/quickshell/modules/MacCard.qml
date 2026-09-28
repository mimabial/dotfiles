import QtQuick
import ".."

PopupCard {
    id: root
    required property string settings
    required property string settingsPopup
    default property alias items: list.data
    contentWidth: Style.px(300); contentHeight: body.implicitHeight + padding * 2; keyboardHint: ""
    Column {
        id: body
        width: parent.width; spacing: Style.xs
        Column { id: list; width: parent.width; spacing: Style.xs }
        PopupSeparator { shell: root.shell }
        PopupRow { width: parent.width; shell: root.shell; title: root.settings + " Settings…"; onClicked: root.shell.togglePopup(root.settingsPopup) }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs as Bar
import "altscape/panel" as Altscape

Bar.PopupCard {
    id: root
    readonly property var service: shell.altscape
    popupName: "altscape"
    padding: 0
    keyboardHint: ""
    Altscape.PanelView {
        width: parent.width
        svc: root.service
    }
}

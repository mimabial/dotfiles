pragma ComponentBehavior: Bound

import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    css: "games"
    text: ""
    tooltip: "Games and MangoHud"
    onClicked: shell.togglePopup("games")

    GamePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

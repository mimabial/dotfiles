import QtQuick
import ".."

NotificationButton {
    id: root
    property bool popupsAllowed: true
    popupEnabled: root.popupsAllowed
}

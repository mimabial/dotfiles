import QtQuick
import QtQuick.Layouts
import ".."

NotificationButton {
    id: root
    property bool popupsAllowed: true
    popupEnabled: root.popupsAllowed
}

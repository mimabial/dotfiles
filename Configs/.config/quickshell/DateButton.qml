pragma ComponentBehavior: Bound
import QtQuick

BarButton {
    id: root
    css: "clock.date"
    property bool popupEnabled: true
    property string dateFormat: "ddd\ndd\nMMM"
    property string dateFormatAlt: "dd|\nMM|\nyy "
    text: Qt.formatDate(shell.clock.date, shell.prefs.mainDateNumeric ? dateFormatAlt : dateFormat)
    onClicked: button => {
        if (button === Qt.RightButton) shell.prefs.mainDateNumeric = !shell.prefs.mainDateNumeric
        else shell.togglePopup("clock")
    }
    ClockPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}

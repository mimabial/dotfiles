pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showDate: false
    // layouts set their own date formats; the shared store flag picks the pair
    property string dateFormat: "ddd\ndd\nMMM"
    property string dateFormatAlt: "dd|\nMM|\nyy "
    shell: root.shell; css: "datetime"; Layout.fillWidth: true
    // the date's popup anchors to a slot the drawer would otherwise destroy
    holdOpen: ["clock", "timer"].includes(root.shell.popupName)
    slots: root.showDate ? [timeSlot, dateSlot] : [timeSlot]

    Component { id: timeSlot; ClockButton {
        shell: root.shell; kind: "main"; css: "clock.time"
        timerPopup: true; popupEnabled: root.popupsAllowed
    } }
    Component { id: dateSlot; BarButton {
        id: dateButton
        shell: root.shell; css: "clock.date"
        // right-click swaps the written month for a numeric one
        text: Qt.formatDate(root.shell.clock.date, root.shell.store.mainDateNumeric ? root.dateFormatAlt : root.dateFormat)
        onClicked: button => button === Qt.RightButton
            ? root.shell.store.mainDateNumeric = !root.shell.store.mainDateNumeric
            : root.shell.togglePopup("clock")
        ClockPopup { anchorItem: dateButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
}

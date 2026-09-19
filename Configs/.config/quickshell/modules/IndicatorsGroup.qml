import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    required property var shell
    property bool popupsAllowed: true
    property bool caffeineActiveOnly: true
    spacing: 0
    // a child that stays visible on its own must keep the group visible too
    readonly property bool shown: dnd.paused || sunset.sunsetActive || recorder.recording || caffeine.visible

    // each button subscribes to the refresh bus itself through its `indicator`
    NotificationButton {
        id: dnd
        shell: root.shell
        // Two owners create competing focus grabs and immediately dismiss both.
        popupEnabled: root.popupsAllowed
            && !root.shell.barModules.includes("notification")
            && !root.shell.barModules.includes("notification-group")
        indicator: "dnd"
        activeOnly: true; polling: false; Layout.fillHeight: true
        Component.onCompleted: dnd.refresh()
    }
    HyprsunsetButton {
        id: sunset
        shell: root.shell; popupsAllowed: root.popupsAllowed
        activeOnly: true; Layout.fillHeight: true
    }
    ScreenRecordButton {
        id: recorder
        shell: root.shell; popupsAllowed: root.popupsAllowed
        activeOnly: true; Layout.fillHeight: true
    }
    CaffeineButton {
        id: caffeine
        shell: root.shell; popupsAllowed: root.popupsAllowed
        activeOnly: root.caffeineActiveOnly; Layout.fillHeight: true
    }
}

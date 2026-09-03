import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    required property var shell
    property bool popupsAllowed: true
    spacing: 0
    readonly property bool shown: dnd.paused || sunset.sunsetActive || recorder.recording || caffeine.awake

    // each button subscribes to the refresh bus itself through its `indicator`
    NotificationButton {
        id: dnd
        shell: root.shell; popupEnabled: root.popupsAllowed
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
        activeOnly: true; polling: false; Layout.fillHeight: true
    }
    CaffeineButton {
        id: caffeine
        shell: root.shell; popupsAllowed: root.popupsAllowed
        activeOnly: true; Layout.fillHeight: true
    }
}

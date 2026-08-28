import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root
    required property var shell
    property bool popupsAllowed: true
    spacing: 0
    readonly property bool shown: dnd.paused || sunset.sunsetActive || recorder.recording || caffeine.awake

    function refresh(target) {
        const name = String(target || "all")
        if (name === "all" || name === "dnd") dnd.refresh()
        if (name === "all" || name === "screenrecord") recorder.refresh()
    }

    Component.onCompleted: refresh("all")
    Connections {
        target: root.shell
        function onIndicatorRefreshSerialChanged() {
            root.refresh(root.shell.indicatorRefreshTarget)
        }
    }

    NotificationButton {
        id: dnd
        shell: root.shell; popupEnabled: root.popupsAllowed
        activeOnly: true; polling: false; Layout.fillHeight: true
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

import QtQuick
import ".."

BarButton {
    id: root
    property bool popupEnabled: true
    css: "backlight"
    text: Backlight.icon
    readonly property var displayPanel: displayPanelLoader.item
    tooltip: root.displayPanel && root.displayPanel.activeProfile
        ? "Display profile: " + root.displayPanel.activeProfile + "\nBacklight: " + Backlight.percent + "%"
        : "Backlight level: " + Backlight.percent + "%\nUsing: " + Backlight.device
    radius: shell.moduleRadius
    onClicked: shell.togglePopup("monitor")
    onWheeled: delta => {
        shell.run(["hyprshell", "brightness-control.sh", delta > 0 ? "i" : "d"], Backlight.refresh)
    }

    // 153KB of QML for a panel that is only ever seen after a click. Loading it
    // by url on first open keeps its compile out of bar startup; `shell` is
    // required, so it has to be an initial property rather than a later binding.
    Loader {
        id: displayPanelLoader
        property bool everOpened: false
        active: displayPanelLoader.everOpened
        asynchronous: true
        visible: false
        onActiveChanged: if (displayPanelLoader.active && String(displayPanelLoader.source) === "")
            displayPanelLoader.setSource(Qt.resolvedUrl("../monitor/DisplayPanel.qml"),
                { anchorItem: root, shell: root.shell, bar: root.shell })
        Connections {
            target: root.shell
            function onPopupNameChanged() {
                if (root.shell.popupName === "monitor") displayPanelLoader.everOpened = true
            }
        }
    }
}

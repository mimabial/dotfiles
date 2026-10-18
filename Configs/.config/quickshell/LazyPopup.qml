import QtQuick

Loader {
    id: root
    required property var shell
    required property string popup
    required property var owners
    property bool popupsAllowed: true
    property bool requestedOnce: false
    readonly property bool hostedByModule: owners.some(id => shell.liveModules.includes(id))
    active: requestedOnce && !hostedByModule
    visible: false
    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.popupsAllowed && root.shell.popupName === root.popup) root.requestedOnce = true
        }
    }
}

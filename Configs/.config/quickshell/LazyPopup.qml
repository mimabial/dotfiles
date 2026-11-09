import QtQuick

Loader {
    id: root
    required property var shell
    required property string popupName
    property var sharedWith: []
    required property var owners
    property bool popupEnabled: true
    property bool requestedOnce: false
    readonly property bool hostedByModule: owners.some(id => shell.liveModules.includes(id))
    active: requestedOnce && !hostedByModule
    visible: false
    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.popupEnabled && [root.popupName].concat(root.sharedWith).includes(root.shell.popupName)) root.requestedOnce = true
        }
    }
}

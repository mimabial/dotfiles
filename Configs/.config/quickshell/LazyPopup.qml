import QtQuick

// Creates a named popup the first time it is asked for, and stands down while a
// module that hosts the same popup is live on the bar, so only one instance answers.
Loader {
    id: root
    required property var shell
    required property string popup
    required property var owners
    property bool popupsAllowed: true
    property bool everOpened: false
    active: everOpened && !owners.some(id => shell.liveModules.includes(id))
    visible: false
    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.popupsAllowed && root.shell.popupName === root.popup) root.everOpened = true
        }
    }
}

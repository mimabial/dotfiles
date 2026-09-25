pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool loaded: false
    readonly property var vault: shell.bitwarden
    opensPopup: true
    css: "bitwarden"
    text: vault.status === "unlocked" ? "\u{f07f5}" : vault.status === "locked" ? "\u{f135d}" : "\u{f060e}"
    tooltip: "Bitwarden · " + (vault.status || "not checked yet") + (vault.status === "unlocked" ? "\nRight-click to lock" : "")
    active: shell.popupName === "bitwarden"
    onClicked: button => {
        if (button === Qt.RightButton) return root.vault.lock()
        root.loaded = true
        root.shell.togglePopup("bitwarden")
    }
    Connections {
        target: root.shell
        function onPopupNameChanged() { if (root.popupsAllowed && root.shell.popupName === "bitwarden") root.loaded = true }
    }
    Loader {
        active: root.loaded; visible: false
        sourceComponent: Component { BitwardenPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
}

pragma ComponentBehavior: Bound
import QtQuick

PopupCard {
    id: root
    popupName: "tray-manage"
    contentWidth: Style.px(280)
    property var icons: []
    property var hostedEntries: []
    signal restore(string key)

    Column {
        id: rows
        width: parent.width
        spacing: Style.sectionGap
        PopupToggleRow {
            width: rows.width; shell: root.shell
            title: "Show system icons"
            checked: root.shell.prefs.trayShowIcons
            onToggled: root.shell.prefs.trayShowIcons = !checked
        }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { width: rows.width; shell: root.shell; text: "BAR WIDGETS"; visible: root.hostedEntries.length > 0 }
            Repeater {
                model: root.hostedEntries
                delegate: PopupRow {
                    required property var modelData
                    width: rows.width; shell: root.shell
                    title: modelData.key.split(":").pop()
                    value: "Restore"
                    onClicked: root.restore(modelData.key)
                }
            }
        }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { width: rows.width; shell: root.shell; text: "SYSTEM ICONS" }
            Repeater {
                model: root.icons
                delegate: PopupRow {
                    required property var modelData
                    readonly property string iconId: String(modelData.id || "")
                    width: rows.width; shell: root.shell
                    title: modelData.title || iconId
                    detail: root.shell.trayPinned.includes(iconId) ? "Right-click to unpin" : "Right-click to pin"
                    iconSource: modelData.icon
                    value: (root.shell.trayPinned.includes(iconId) ? "PIN " : "") + (root.shell.trayHidden.includes(iconId) ? "○" : "◉")
                    opacity: root.shell.prefs.trayShowIcons ? 1 : .5
                    onClicked: button => button === Qt.RightButton ? root.shell.toggleTrayPin(iconId) : root.shell.toggleTrayIcon(iconId)
                }
            }
        }
    }
}

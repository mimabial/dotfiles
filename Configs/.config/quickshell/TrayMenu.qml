import QtQuick
import Quickshell

PopupCard {
    id: root
    popupName: "tray"
    contentWidth: 260

    property var handle: null
    property string label: ""
    property var openSub: null
    property Item openRow: null

    property QsMenuOpener opener: QsMenuOpener { menu: root.handle }
    extraGrabWindows: [flyout, flyout2, flyout3]

    onOpenChanged: if (!open) { openSub = null; openRow = null }

    property TrayFlyout flyout: TrayFlyout {
        shell: root.shell
        handle: root.openSub
        anchorItem: root.openRow
        onPicked: root.shell.closePopup()
    }
    property TrayFlyout flyout2: TrayFlyout {
        shell: root.shell
        handle: root.flyout.openSub
        anchorItem: root.flyout.openRow
        onPicked: root.shell.closePopup()
    }
    property TrayFlyout flyout3: TrayFlyout {
        shell: root.shell
        handle: root.flyout2.openSub
        anchorItem: root.flyout2.openRow
        onPicked: root.shell.closePopup()
    }

    Column {
        id: menuColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: 2

        PopupSection { shell: root.shell; text: root.label }

        Repeater {
            model: root.opener.children
            delegate: Item {
                id: entry
                required property var modelData
                width: menuColumn.width
                implicitHeight: entry.modelData.isSeparator ? sep.implicitHeight : row.implicitHeight

                PopupSeparator { id: sep; visible: entry.modelData.isSeparator; shell: root.shell; width: parent.width }

                PopupRow {
                    id: row
                    visible: !entry.modelData.isSeparator
                    width: parent.width; shell: root.shell
                    title: entry.modelData.text
                    iconSource: entry.modelData.icon
                    active: root.openSub === entry.modelData
                    color: row.highlight
                    value: entry.modelData.hasChildren ? "›"
                        : entry.modelData.buttonType === QsMenuButtonType.CheckBox
                            ? (entry.modelData.checkState === Qt.Checked ? "✓" : "")
                            : entry.modelData.buttonType === QsMenuButtonType.RadioButton
                                ? (entry.modelData.checkState === Qt.Checked ? "◉" : "○")
                                : ""
                    opacity: entry.modelData.enabled ? 1 : .4
                    onHoveredChanged: {
                        if (!hovered || !entry.modelData.enabled) return
                        if (entry.modelData.hasChildren) {
                            root.openSub = entry.modelData
                            root.openRow = row
                        } else {
                            root.openSub = null
                            root.openRow = null
                        }
                    }
                    onClicked: {
                        if (!entry.modelData.enabled) return
                        if (entry.modelData.hasChildren) {
                            const same = root.openSub === entry.modelData
                            root.openSub = same ? null : entry.modelData
                            root.openRow = same ? null : row
                            return
                        }
                        entry.modelData.triggered()
                        root.shell.closePopup()
                    }
                }
            }
        }
    }
}

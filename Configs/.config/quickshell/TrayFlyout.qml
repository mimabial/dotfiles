import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property var shell
    property Item anchorItem: null
    property var handle: null
    property int contentWidth: 240
    property int padding: Style.popupPadding
    readonly property bool open: handle !== null && anchorItem !== null
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    property var openSub: null
    property Item openRow: null
    signal picked

    property QsMenuOpener opener: QsMenuOpener { menu: root.open ? root.handle : null }

    onOpenChanged: if (!open) { openSub = null; openRow = null }

    visible: open
    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: flyColumn.implicitHeight + padding * 2

    anchor {
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1; rect.height: 1
        onAnchoring: {
            if (!root.anchorItem || !root.anchorWindow) return
            const point = root.anchorWindow.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width, 0)
            anchor.rect.x = Math.round(point.x); anchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.shell.alpha(root.shell.role("bg", "#0c1021"), 0.94)
        border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        border.width: 1
        radius: root.shell.rounding

        Column {
            id: flyColumn
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: root.padding
            spacing: 2
            Repeater {
                model: root.opener.children
                delegate: Item {
                    id: entry
                    required property var modelData
                    width: flyColumn.width
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
                            root.openSub = entry.modelData.hasChildren ? entry.modelData : null
                            root.openRow = entry.modelData.hasChildren ? row : null
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
                            root.picked()
                        }
                    }
                }
            }
        }
    }
}

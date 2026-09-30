pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// Mission Control's desktop row, reduced to one chip per workspace: a click
// switches to it, a dropped window card moves there.
Item {
    id: strip

    required property var controller
    required property string screenName
    required property real chipHeight
    readonly property var workspaces: strip.controller.workspacesForScreen(strip.screenName)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: Style.spacing.sm

        Repeater {
            model: strip.workspaces.regular
            delegate: WorkspaceChip {}
        }

        WorkspaceChip { modelData: null }

        Rectangle {
            visible: strip.workspaces.special.length > 0
            width: Style.normalBorderWidth
            height: strip.chipHeight
            color: Color.menu.border
        }

        Repeater {
            model: strip.workspaces.special
            delegate: WorkspaceChip {}
        }
    }

    component WorkspaceChip: Item {
        id: chip

        required property var modelData
        readonly property string name: chip.modelData ? String(chip.modelData.name || "") : ""
        readonly property bool shown: chip.modelData !== null && strip.controller.isWorkspaceShown(chip.modelData)
        readonly property bool highlighted: drop.containsDrag || pointer.containsMouse
        readonly property bool numbered: chip.modelData !== null && chip.name.indexOf("special:") !== 0 && /^\d+$/.test(label.text)

        implicitHeight: strip.chipHeight
        implicitWidth: chip.modelData === null || chip.numbered
            ? chip.implicitHeight : Math.max(chip.implicitHeight, label.implicitWidth + Style.spacing.controlPaddingX * 2)

        Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            opacity: chip.modelData === null && !chip.highlighted ? Style.popupSurfaceOpacity : 1
            color: chip.highlighted ? Color.menu.selectedBackground
                : (chip.shown ? Style.selectionFillFor(Color.menu.text, Color.accent)
                    : (chip.modelData === null ? Style.normalFillFor(Color.menu.background, Color.accent)
                        : Color.alpha(Color.menu.background, Style.selectedFillAlpha)))
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: chip.modelData === null
                ? "+"
                : (chip.name.indexOf("special:") === 0
                    ? chip.name.slice("special:".length)
                    : strip.controller.formatWorkspaceLabel(chip.name))
            textFormat: Text.PlainText
            color: chip.highlighted ? Color.menu.selectedText
                : (chip.shown ? Color.accent : Color.menu.text)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: strip.controller.showWorkspace(chip.modelData)
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: strip.controller.windowDragKeys
            onDropped: function (event) {
                strip.controller.moveWindowTo((event.source as WindowCard).modelData, chip.modelData);
                event.accept();
            }
        }
    }
}

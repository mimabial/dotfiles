import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: root
    required property var shell
    readonly property var box: shell.style.box("tray")
    property int iconSize: 16
    property int iconSpacing: vertical ? 2 : 6
    readonly property int scaledIcon: Math.round(iconSize * Style.scale)
    readonly property int scaledSpacing: Math.round(iconSpacing * Style.scale)
    property bool vertical: false
    property bool popupsAllowed: true
    property var menuHandle: null
    property Item menuAnchor: null
    property string menuLabel: ""
    property bool framed: vertical
    property color fill: boxColor("fill")
    property color outline: boxColor("outline")
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
    implicitWidth: icons.implicitWidth + spanX
    implicitHeight: icons.implicitHeight + spanY
    function boxColor(key) { const spec = box[key]; return !spec ? "transparent" : Array.isArray(spec) ? shell.alpha(shell.role(spec[0], shell.foreground), spec[1]) : shell.role(spec, shell.foreground) }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
        anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
        visible: root.framed; radius: root.shell.moduleRadius
        color: root.fill; border.color: root.outline
        border.width: trayEdge.replacesOutline ? 0 : root.box.border > 0 ? root.box.border : root.outline.a > 0 ? 1 : 0
    }
    Grid {
        id: icons
        anchors.centerIn: parent
        columns: root.vertical ? 1 : items.count
        spacing: root.scaledSpacing
        Repeater {
            id: items
            model: SystemTray.items
            delegate: Item {
                id: slot
                required property var modelData
                property bool shown: modelData.status !== Status.Passive
                width: shown ? root.scaledIcon : 0
                height: shown ? root.scaledIcon : 0
                visible: shown
                IconImage { anchors.centerIn: parent; implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon; source: slot.modelData.icon }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    onClicked: event => {
                        if (event.button === Qt.LeftButton) slot.modelData.activate()
                        else if (event.button === Qt.MiddleButton) slot.modelData.secondaryActivate()
                        else if (slot.modelData.hasMenu) {
                            root.menuHandle = slot.modelData.menu
                            root.menuAnchor = slot
                            root.menuLabel = slot.modelData.title || slot.modelData.id
                            root.shell.togglePopup("tray")
                        }
                    }
                    onWheel: event => slot.modelData.scroll(event.angleDelta.y, false)
                }
            }
        }
    }
    ModuleEdge { id: trayEdge; shell: root.shell }
    TrayMenu {
        shell: root.shell
        anchorItem: root.menuAnchor ? root.menuAnchor : root
        handle: root.menuHandle
        label: root.menuLabel
        popupEnabled: root.popupsAllowed
    }
}

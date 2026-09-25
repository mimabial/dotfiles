pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

Item {
    id: root
    required property var shell
    readonly property var box: shell.style.box("taskbar")
    property bool allWorkspaces: false
    property bool framed: false
    property bool vertical: false
    property int iconSize: 18
    // "iconSize" in the style file wins, as it does for the tray
    readonly property int scaledIcon: Math.round(box.iconSize !== undefined ? box.iconSize : iconSize)
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
    implicitWidth: windows.implicitWidth + spanX
    implicitHeight: windows.implicitHeight + spanY

    Grid {
        id: windows
        anchors.centerIn: parent
        columns: root.vertical ? 1 : tasks.count
        Repeater {
            id: tasks
            model: root.allWorkspaces ? Hyprland.toplevels : Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.toplevels : null
            delegate: Item {
                id: window
                required property var modelData
                readonly property bool active: modelData.activated
                visible: !!modelData.wayland && !(modelData.workspace && modelData.workspace.name.startsWith("special:"))
                readonly property var box: root.shell.style.box(active ? "#taskbar button.active" : "#taskbar button")
                property var entry: null
                function act(button) {
                    const target = modelData.wayland, address = String((modelData.lastIpcObject || {}).address || "")
                    if (button === Qt.LeftButton && address) Quickshell.execDetached(["hyprctl", "eval", "local w=hl.get_config('cursor.no_warps');hl.config({cursor={no_warps=true}});hl.exec_scheduled_prop_refresh_immediately();hl.dispatch(hl.dsp.focus({window='address:" + address + "'}));hl.config({cursor={no_warps=w}})"])
                    else if (button === Qt.LeftButton) target.activate()
                    else if (button === Qt.MiddleButton) target.close()
                    else target.fullscreen = !target.fullscreen
                }
                function refreshEntry() { const ipc = modelData.lastIpcObject || {}, name = String(ipc.class || ipc.initialClass || ""); entry = name ? DesktopEntries.heuristicLookup(name) : null }
                Component.onCompleted: refreshEntry()
                Connections { target: window.modelData; function onLastIpcObjectChanged() { window.refreshEntry() } }
                Connections { target: DesktopEntries; function onApplicationsChanged() { window.refreshEntry() } }
                function boxColor(key, hoverKey, fallback) {
                    const hovered = mouse.containsMouse && box.hover && hoverKey in box.hover
                    const spec = hovered ? box.hover[hoverKey] : box[key]
                    if (!spec) return "transparent"
                    return Array.isArray(spec) ? root.shell.alpha(root.shell.role(spec[0], fallback), spec[1]) : root.shell.role(spec, fallback)
                }
                width: root.scaledIcon + box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
                height: root.scaledIcon + box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
                Rectangle {
                    id: frame
                    anchors.fill: parent
                    anchors.topMargin: window.box.margin[0]; anchors.rightMargin: window.box.margin[1]
                    anchors.bottomMargin: window.box.margin[2]; anchors.leftMargin: window.box.margin[3]
                    radius: root.framed ? root.shell.moduleRadius : 0
                    color: window.boxColor("fill", "fill", root.shell.background)
                    border.color: root.framed || window.active ? window.boxColor("outline", "outline", root.shell.foreground) : "transparent"
                    border.width: taskEdge.replacesOutline ? 0 : border.color.a > 0 ? window.box.border : 0
                }
                ModuleEdge { id: taskEdge; shell: root.shell; host: window; hovered: mouse.containsMouse; active: window.active }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 2
                    visible: !root.framed && !taskEdge.replacesOutline && frame.border.width === 0
                    color: window.active || mouse.containsMouse ? window.boxColor("outline", "outline", root.shell.accent) : "transparent"
                }
                IconImage {
                    anchors.centerIn: parent; implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon
                    source: window.entry ? Quickshell.iconPath(window.entry.icon, true) : Quickshell.iconPath("application-x-executable", true)
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    onClicked: event => window.act(event.button)
                }
                BarTooltip { anchorItem: window; shell: root.shell; text: window.modelData.title; hovered: mouse.containsMouse }
            }
        }
    }
    ModuleEdge { shell: root.shell; host: root }
}
